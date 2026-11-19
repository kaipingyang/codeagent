#' @title shinychat history over codeagent's session log
#' @description A [shinychat::ConversationStore] whose backend is the project's
#'   codeagent session log: the history column lists every session of the
#'   project (earlier ones included) without a second copy of any conversation.
#'   For personal use (`codeagent_app()`); deployed host apps keep
#'   `shinychat::history_options()` with their own store.
#'
#' The store only reads and writes `<uuid>.jsonl` files of one project's session
#' directory, through `.find_session_path(id, cwd)` with a validated id.
#' @name history_store
#' @keywords internal
NULL

.history_local_user <- function() {
  u <- tryCatch(unname(Sys.info()[["user"]]), error = function(e) NULL)
  if (is.character(u) && length(u) == 1L && nzchar(u)) u else "local"
}

.history_iso <- function(ms) {
  if (is.null(ms) || !length(ms) || is.na(ms)) return(NULL)
  format(as.POSIXct(ms / 1000, origin = "1970-01-01", tz = "UTC"),
         "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
}

# shinychat's own grouping: consecutive turns of one effective role form one
# node, a user turn made only of tool results counting as the assistant's.
.history_turn_role <- function(turn) {
  contents <- tryCatch(turn@contents, error = function(e) list())
  if (length(contents) && all(vapply(contents, function(x)
        S7::S7_inherits(x, ellmer::ContentToolResult), logical(1L))))
    "assistant"
  else tryCatch(turn@role, error = function(e) "assistant")
}

# A linear conversation record (schema 1) from turns as shown.
.history_record <- function(id, session_id, turns, info) {
  roles <- vapply(turns, .history_turn_role, character(1L))
  nodes <- list(); prev <- NULL; start <- 1L; k <- 0L
  for (i in seq_along(turns)) {
    if (i < length(turns) && identical(roles[[i]], roles[[i + 1L]])) next
    k <- k + 1L
    nid <- sprintf("n_%04d", k)
    nodes[[nid]] <- list(
      parent = prev, children = list(),
      turns = lapply(turns[start:i], ellmer::contents_record), ui = NULL)
    if (!is.null(prev)) nodes[[prev]]$children <- list(nid)
    prev <- nid; start <- i + 1L
  }
  groups <- rle(roles)$values
  list(
    schema_version = 1L, id = id,
    title = info$custom_title %||% info$summary %||% "New chat",
    title_source = info$title_source,
    response_count = sum(groups == "assistant"),
    created_at = .history_iso(info$created_at %||% info$last_modified),
    updated_at = .history_iso(info$last_modified),
    client_info = list(), nodes = nodes, current_leaf = prev,
    values = list(codeagent_session_id = session_id),
    bookmark_state_id = NULL)
}

.SessionLogStore <- R6::R6Class(".SessionLogStore",
  inherit = shinychat::ConversationStore,
  public = list(
    cwd = NULL,
    # Logs without an owner (all written before owners were recorded) belong
    # to the account that keeps the codeagent directory.
    default_owner = NULL,

    initialize = function(cwd = getwd(), default_owner = .history_local_user()) {
      self$cwd <- cwd
      self$default_owner <- default_owner
      private$index <- new.env(parent = emptyenv())
      private$cache <- new.env(parent = emptyenv())
    },

    # Per browser session: what get() returns is gated with this session's
    # Data Shield. An unbound store returns no conversation.
    bind = function(chat, settings) {
      force(chat); force(settings)
      private$tools <- function() tryCatch(chat$get_tools(), error = function(e) list())
      private$present <- function(turns) .presentation_turns(turns, settings, chat)
      invisible(self)
    },

    list = function(partition) {
      infos <- Filter(function(i) private$owned(i, partition), private$infos())
      metas <- lapply(infos, function(i) {
        id <- i$shinychat_id %||% i$session_id
        assign(id, i$session_id, envir = private$index)
        list(id = id,
             title = i$custom_title %||% i$summary,
             created_at = .history_iso(i$created_at %||% i$last_modified),
             updated_at = .history_iso(i$last_modified),
             size_bytes = as.double(i$file_size %||% 0))
      })
      if (length(metas)) {
        created <- vapply(metas, function(m) m$created_at %||% "", "")
        metas <- metas[order(created, decreasing = TRUE)]
      }
      metas
    },

    get = function(partition, id) {
      if (is.null(private$present)) return(NULL)
      info <- private$resolve(partition, id)
      if (is.null(info)) return(NULL)
      shown <- tryCatch(.read_session_display_turns(info$session_id, self$cwd,
                                                    tools = private$tools()),
                        error = function(e) NULL)
      if (is.null(shown)) return(NULL)
      turns <- tryCatch(private$present(shown$turns), error = function(e) NULL)
      if (is.null(turns)) return(NULL)
      .history_record(info$shinychat_id %||% info$session_id, info$session_id,
                      turns, info)
    },

    put = function(partition, record) invisible(NULL),

    delete = function(partition, id) invisible(NULL)
  ),

  private = list(
    tools = NULL, present = NULL, index = NULL, cache = NULL,

    owned = function(info, partition) {
      scope <- tryCatch(partition$scope, error = function(e) NULL)
      is.character(scope) && length(scope) == 1L &&
        identical(info$user %||% self$default_owner, scope)
    },

    # Session infos of this project, cached by file size + mtime. Sessions with
    # nothing said in them (no prompt, no title) are left out.
    infos = function() {
      dir <- .get_project_session_dir(self$cwd)
      files <- tryCatch(list.files(dir, pattern = "\\.jsonl$", full.names = TRUE),
                        error = function(e) character(0))
      out <- list()
      for (f in files) {
        sid <- tools::file_path_sans_ext(basename(f))
        if (is.null(.validate_uuid(sid))) next
        fi <- file.info(f)
        key <- paste(fi$size, as.numeric(fi$mtime))
        hit <- private$cache[[sid]]
        if (is.null(hit) || !identical(hit$key, key)) {
          hit <- list(key = key, info = tryCatch(.read_session_info(sid, f),
                                                 error = function(e) NULL))
          assign(sid, hit, envir = private$cache)
        }
        i <- hit$info
        if (!is.null(i) && !is.null(i$custom_title %||% i$first_prompt))
          out[[length(out) + 1L]] <- i
      }
      out
    },

    # An id from shinychat (the browser) -> the session's info, or NULL. Only a
    # session UUID or a shinychat record id the list produced resolves; the
    # session must belong to the partition.
    resolve = function(partition, id) {
      if (!is.character(id) || length(id) != 1L || is.na(id)) return(NULL)
      sid <- if (!is.null(.validate_uuid(id))) id
             else if (grepl("^c_[0-9a-f]{1,64}$", id)) {
               if (!exists(id, envir = private$index, inherits = FALSE))
                 self$list(partition)
               get0(id, envir = private$index, inherits = FALSE)
             }
      if (is.null(sid)) return(NULL)
      path <- .find_session_path(sid, self$cwd)
      if (is.null(path)) return(NULL)
      info <- tryCatch(.read_session_info(sid, path), error = function(e) NULL)
      if (is.null(info) || !private$owned(info, partition)) return(NULL)
      info
    }
  )
)
