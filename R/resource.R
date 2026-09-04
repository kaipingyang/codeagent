#' @title Three-Layer Resource Management
#' @description Manages large tool output to prevent context bloat.
#'
#'   * **Layer 1** (utils.R): Per-tool character truncation via
#'     `truncate_tool_result()`.  Already applied at tool execution time.
#'   * **Layer 2** (this file): Optional disk-persistence helper for very large
#'     results. It is intentionally NOT wired into production until file
#'     permissions, retention/cleanup, path disclosure, and protected-data
#'     policy are defined; built-in truncation remains the active protection.
#'   * **Layer 3** (this file): `ContentReplacementState` -- global budget
#'     tracker that replaces the largest old tool results across turns when
#'     total context exceeds a soft ceiling.
#' @name resource
#' @keywords internal
NULL

# Soft ceiling before L3 replacement kicks in (tokens)
.RESOURCE_SOFT_CEILING <- 80000L

# L2 threshold: persist to disk if result > this many chars
.L2_PERSIST_THRESHOLD <- 5000L

# L2 preview length kept inline
.L2_PREVIEW_LEN <- 2000L

# ---------------------------------------------------------------------------
# Layer 2: Disk persistence
# ---------------------------------------------------------------------------

#' Persist a large tool result to disk (Layer 2)
#'
#' If `content` exceeds `.L2_PERSIST_THRESHOLD` characters, writes it to
#' `~/.codeagent/tool-results/<tool_id>.txt` and returns a short preview
#' plus the path.  Small results are returned unchanged.
#'
#' @param content Character(1). Tool output.
#' @param tool_id Character(1). Unique identifier for this tool call.
#' @return Character(1). Possibly shortened content with path reference.
#' @keywords internal
persist_large_result <- function(content, tool_id) {
  if (nchar(content) <= .L2_PERSIST_THRESHOLD) return(content)

  dir  <- file.path(.get_codeagent_dir(), "tool-results")
  dir.create(dir, showWarnings = FALSE, recursive = TRUE)
  path <- file.path(dir, paste0(tool_id, ".txt"))
  tryCatch(writeLines(content, path), error = function(e) NULL)

  preview <- substr(content, 1L, .L2_PREVIEW_LEN)
  paste0(preview, "\n...[full output saved to ", path, "; ",
         nchar(content), " total chars]")
}

# ---------------------------------------------------------------------------
# Layer 3: ContentReplacementState
# ---------------------------------------------------------------------------

#' Global context budget manager (Layer 3)
#'
#' Tracks total estimated token usage across all turns and replaces the
#' largest tool results with a placeholder when the soft ceiling is exceeded.
#' This mirrors Claude Code's `ContentReplacementState`.
#'
#' @export
ContentReplacementState <- R6::R6Class(
  "ContentReplacementState",

  private = list(
    replaced = character(0),   # tool_use_ids already replaced
    frozen   = character(0),   # ids that must NOT be replaced
    ceiling  = NULL            # soft token ceiling (set in initialize)
  ),

  public = list(

    #' @description Create a new state object.
    #' @param soft_ceiling Integer. Token threshold to trigger replacement.
    initialize = function(soft_ceiling = .RESOURCE_SOFT_CEILING) {
      private$ceiling <- as.integer(soft_ceiling)
    },

    #' @description Freeze a result (exclude it from replacement).
    #' @param tool_use_id Character.
    freeze = function(tool_use_id) {
      private$frozen <- unique(c(private$frozen, tool_use_id))
      invisible(self)
    },

    #' @description Check usage and replace large old results if over ceiling.
    #' @param chat An `ellmer::Chat` object (modified in place).
    #' @return Invisibly TRUE when history changed, FALSE otherwise.
    maybe_replace = function(chat) {
      total <- estimate_tokens(chat)
      if (total <= private$ceiling) return(invisible(FALSE))

      turns <- .safe_get_turns(chat)
      if (length(turns) == 0L) return(invisible(FALSE))
      pending_ids <- character(0)
      modified <- FALSE

      repeat {
        candidates <- list()
        for (turn_idx in seq_along(turns)) {
          contents <- tryCatch(
            turns[[turn_idx]]@contents,
            error = function(e) list()
          )
          for (content_idx in seq_along(contents)) {
            content <- contents[[content_idx]]
            if (!identical(.compact_content_type(content),
                           "ContentToolResult")) next
            tool_use_id <- tryCatch(
              as.character(content@request@id %||% ""),
              error = function(e) ""
            )
            state_id <- tool_use_id
            if (!nzchar(state_id))
              state_id <- paste0("turn:", turn_idx, ":", content_idx)
            if (state_id %in% c(private$replaced, pending_ids)) next
            if (nzchar(tool_use_id) && tool_use_id %in% private$frozen) next
            text <- tryCatch(
              paste(as.character(content@value %||% ""), collapse = "\n"),
              error = function(e) ""
            )
            size <- nchar(text)
            if (size < 500L) next
            candidates[[length(candidates) + 1L]] <- list(
              turn_idx = turn_idx,
              content_idx = content_idx,
              state_id = state_id,
              size = size
            )
          }
        }

        if (length(candidates) == 0L) break
        sizes <- vapply(candidates, function(x) x$size, integer(1L))
        target <- candidates[[which.max(sizes)]]
        changed <- tryCatch({
          turns[[target$turn_idx]]@contents[[target$content_idx]]@value <-
            "[Tool result replaced to save context space]"
          TRUE
        }, error = function(e) FALSE)
        if (!changed) break
        modified <- TRUE
        pending_ids <- unique(c(pending_ids, target$state_id))
        if (.estimate_turns_tokens(turns) <= private$ceiling) break
      }

      if (!modified) return(invisible(FALSE))
      set_ok <- tryCatch({
        chat$set_turns(turns)
        TRUE
      }, error = function(e) FALSE)
      if (!set_ok) return(invisible(FALSE))
      private$replaced <- unique(c(private$replaced, pending_ids))
      invisible(TRUE)
    },

    #' @description Return IDs of replaced results.
    replaced_ids = function() private$replaced,

    #' @description Reset state.
    reset = function() {
      private$replaced <- character(0)
      private$frozen   <- character(0)
      invisible(self)
    }
  )
)
