# GenUI wiring: when the canvas is on, how its tools are registered, how its
# prompt section and per-turn summary reach the model, and how its state is
# persisted with the session. The Shiny server owns the adapter (one per
# browser session); everything here reads it from `settings$genui`.

# Should this app session get a canvas?
#   disallowed_tools = "genui"          -> never
#   tools = NULL (everything)           -> per-session apps, when installed
#   tools naming genui / a canvas tool  -> yes; warn when it cannot be honoured
# A shared pre-built client only gets one when asked for by name: two browser
# sessions on one Chat would otherwise share a canvas (see GenUIAdapter$bind).
#' @keywords internal
.genui_wanted <- function(settings, per_session = TRUE) {
  removed <- settings$disallowed_tools$remove %||% character(0)
  if (any(.genui_tool_names() %in% removed)) return(FALSE)
  spec <- settings$tools_spec
  explicit <- !is.null(spec) && !isTRUE(spec$all) &&
    any(.genui_tool_names() %in% spec$native)
  default_on <- is.null(spec) || isTRUE(spec$all)
  if (!explicit && !(default_on && isTRUE(per_session))) return(FALSE)
  if (!.genui_available()) {
    if (explicit)
      warning("[codeagent] `tools` asks for \"genui\", but generative UI needs ",
              "shinygenui (plus ggplot2 and DT); the canvas is off. Install ",
              "with pak::pak(c(\"nanxstats/shinygenui\", \"ggplot2\", \"DT\")).",
              call. = FALSE)
    return(FALSE)
  }
  TRUE
}

# Register the canvas tools of the session's adapter. A no-op without one, so
# the CLI and one-shot paths -- which never create an adapter -- never get
# canvas tools.
#' @keywords internal
.register_genui_tools <- function(chat, settings) {
  adapter <- settings$genui
  if (!inherits(adapter, "GenUIAdapter")) return(invisible(chat))
  for (tool in adapter$tools()) chat$register_tool(tool)
  invisible(chat)
}

# -- prompt -----------------------------------------------------------------------

.GENUI_PROMPT_HEADING <- "# Generative UI canvas"

# Only a prepared adapter contributes: building the catalog costs seconds and
# must not happen on whatever path first asks for a system prompt.
#' @keywords internal
.prompt_genui <- function(settings) {
  adapter <- settings$genui
  if (!inherits(adapter, "GenUIAdapter") || !adapter$prepared()) return("")
  fragment <- tryCatch(adapter$prompt_fragment(), error = function(e) "")
  if (!nzchar(fragment)) return("")
  paste0(.GENUI_PROMPT_HEADING, "\n\n", fragment)
}

# Put the canvas section into a live prompt (or take it out), leaving every
# other section byte-for-byte alone -- hosts may have appended their own.
#' @keywords internal
.sync_genui_prompt <- function(chat, settings) {
  current <- tryCatch(chat$get_system_prompt(), error = function(e) NULL)
  if (!is.character(current) || length(current) != 1L) return(invisible(FALSE))
  section <- .prompt_genui(settings)
  start <- regexpr(paste0("\n\n", .GENUI_PROMPT_HEADING, "\n"), current,
                   fixed = TRUE)[[1L]]
  if (start > 0L) {
    # `rest` opens with the heading itself; the section runs to the next
    # top-level heading. The fragment uses only ## and deeper.
    rest <- substr(current, start + 2L, nchar(current))
    nxt <- regexpr("\n\n# ", rest, fixed = TRUE)[[1L]]
    tail <- if (nxt > 0L) substr(rest, nxt, nchar(rest)) else ""
    current <- paste0(substr(current, 1L, start - 1L), tail)
  }
  updated <- if (nzchar(section)) paste0(current, "\n\n", section) else current
  tryCatch({ chat$set_system_prompt(updated); TRUE }, error = function(e) FALSE)
}

# -- results ----------------------------------------------------------------------

#' @keywords internal
.is_genui_result <- function(result) {
  identical(tryCatch(result@extra$codeagent$artifact$kind,
                     error = function(e) NULL), "generative_ui")
}

# -- conversation binding -----------------------------------------------------------

# Every tool request id currently in the chat history.
#' @keywords internal
.chat_request_ids <- function(chat) {
  turns <- tryCatch(chat$get_turns(), error = function(e) list())
  ids <- unlist(lapply(turns, function(turn) {
    contents <- tryCatch(turn@contents, error = function(e) list())
    lapply(contents, function(content) {
      if (inherits(content, "ellmer::ContentToolRequest"))
        tryCatch(content@id, error = function(e) NULL)
    })
  }), use.names = FALSE)
  unique(as.character(ids %||% character()))
}

# -- persistence --------------------------------------------------------------------

# The canvas line of a saved session, or NULL when it has none.
#' @keywords internal
.read_session_genui_state <- function(session_id, cwd = getwd()) {
  path <- .find_session_path(session_id, cwd)
  if (is.null(path)) return(NULL)
  lines <- tryCatch(readLines(path, warn = FALSE), error = function(e) character())
  for (ln in rev(lines)) {
    if (!grepl("\"genui-state\"", ln, fixed = TRUE)) next
    entry <- tryCatch(jsonlite::fromJSON(ln, simplifyVector = FALSE),
                      error = function(e) NULL)
    if (identical(entry[["type"]], "genui-state")) return(entry[["state"]])
  }
  NULL
}

# -- Shiny lifecycle -------------------------------------------------------------------

# Restore the canvas saved with `session_id` into the live adapter. Returns the
# adapter's result, or NULL when there is no adapter.
#' @keywords internal
.genui_restore_session <- function(settings, chat, session_id, cwd) {
  adapter <- settings$genui
  if (!inherits(adapter, "GenUIAdapter")) return(NULL)
  state <- tryCatch(.read_session_genui_state(session_id, cwd),
                    error = function(e) NULL)
  adapter$restore(state, present_ids = .chat_request_ids(chat))
}

#' @keywords internal
.genui_snapshot <- function(settings, chat) {
  adapter <- settings$genui
  if (!inherits(adapter, "GenUIAdapter")) return(NULL)
  adapter$snapshot(.chat_request_ids(chat))
}

# Prepare the session's adapter and bind it to this browser session. Returns
# TRUE when the canvas is live. Failure (a broken install) turns the canvas
# off for this session with a warning; the rest of the app is unaffected.
#' @keywords internal
.genui_attach <- function(settings, session) {
  adapter <- settings$genui
  if (!inherits(adapter, "GenUIAdapter")) return(FALSE)
  tryCatch({
    adapter$prepare()
    adapter$bind(session)
    TRUE
  }, error = function(e) {
    warning("[codeagent] Generative UI is off for this session: ",
            conditionMessage(e), call. = FALSE)
    FALSE
  })
}

# Restore the canvas saved with a session after its chat was restored, and
# tell the user when it could not be restored safely.
#' @keywords internal
.genui_restore_ui <- function(settings, chat, session_id, cwd) {
  res <- tryCatch(.genui_restore_session(settings, chat, session_id, cwd),
                  error = function(e) list(ok = FALSE, message = paste0(
                    "The canvas could not be safely restored: ",
                    .genui_message(e))))
  if (is.list(res) && isFALSE(res$ok)) .ui_toast(res$message, "warning")
  invisible(res)
}

# After the chat history shrank (/rewind, /clear): roll the canvas back to
# match, then persist both at once so a restart cannot revive either half.
#' @keywords internal
.genui_after_history_change <- function(settings, chat, before_ids, cwd,
                                        session_id) {
  adapter <- settings$genui
  if (!inherits(adapter, "GenUIAdapter")) return(invisible(FALSE))
  removed <- setdiff(before_ids, .chat_request_ids(chat))
  if (length(removed)) adapter$forget_requests(removed)
  if (!is.null(session_id))
    tryCatch(save_session(chat, cwd, session_id,
                          genui_state = .genui_snapshot(settings, chat)),
             error = function(e) NULL)
  invisible(TRUE)
}

# End-of-turn bookkeeping, kept out of the coro::async stream body.
#' @keywords internal
.genui_end_turn <- function(settings, chat) {
  adapter <- settings$genui
  if (!inherits(adapter, "GenUIAdapter")) return(invisible(NULL))
  tryCatch(adapter$settle_turn(.chat_request_ids(chat)), error = function(e) NULL)
  invisible(NULL)
}

#' @keywords internal
.genui_begin_turn <- function(settings) {
  if (inherits(settings$genui, "GenUIAdapter")) settings$genui$begin_turn()
  invisible(NULL)
}

#' @keywords internal
.genui_cancel_turn <- function(settings) {
  if (inherits(settings$genui, "GenUIAdapter")) settings$genui$cancel_turn()
  invisible(NULL)
}

#' @keywords internal
.genui_reset <- function(settings) {
  if (inherits(settings$genui, "GenUIAdapter"))
    tryCatch(settings$genui$reset(), error = function(e) NULL)
  invisible(NULL)
}
