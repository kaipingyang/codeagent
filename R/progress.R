# ---------------------------------------------------------------------------
# Tool progress in the Shiny chat
# ---------------------------------------------------------------------------
# A long-running host tool reports what it is doing while it runs, the way
# Claude Code shows a running tool's progress: the chat shows one line per
# running tool above the composer (label, current step, seconds elapsed and,
# when the host knows it, how long it usually takes). Lines appear only after
# `delay` seconds, so quick tools do not flash, and every line is cleared when
# the turn ends (finished, interrupted or failed).

.progress_counter <- new.env(parent = emptyenv())

#' Report a running tool's progress in the chat
#'
#' Call it at the start of a host tool (synchronously, before the tool returns
#' its promise) and keep the handle: `update()` changes the step shown,
#' `done()` removes the line. The line is shown above the chat input of the
#' session that runs the tool, with the seconds elapsed counted in the
#' browser.
#'
#' @param label Character(1). What is running, e.g. `"t_ae_socpt_grd"`.
#' @param step Character(1). The first step shown (optional).
#' @param typical Numeric(1) or `NULL`. Seconds it usually takes; shown as
#'   "usually ~N s" when given.
#' @param delay Seconds before the line appears (default 3).
#' @param session The Shiny session; defaults to the current one.
#' @return A `codeagent_progress` handle: a list with `update(step, typical =
#'   NULL)` and `done()`. Without a session both do nothing.
#' @seealso [codeagent_server()]
#' @export
codeagent_progress <- function(label, step = "", typical = NULL, delay = 3,
                               session = shiny::getDefaultReactiveDomain()) {
  n <- (.progress_counter$n %||% 0L) + 1L
  .progress_counter$n <- n
  id <- paste0("ca_progress_", n)
  send <- function(msg) {
    if (is.null(session)) return(invisible(FALSE))
    tryCatch({ session$sendCustomMessage("ca_tool_progress", msg); invisible(TRUE) },
             error = function(e) invisible(FALSE))
  }
  num <- function(x) if (is.numeric(x) && length(x) == 1L && is.finite(x) && x > 0) round(x) else NULL
  send(list(action = "start", id = id, label = as.character(label)[1], step = as.character(step)[1],
            typical = num(typical), delay = as.numeric(delay)[1]))
  structure(list(
    id = id,
    update = function(step, typical = NULL)
      send(list(action = "update", id = id, step = as.character(step)[1], typical = num(typical))),
    done = function() send(list(action = "done", id = id))
  ), class = "codeagent_progress")
}

# The box the progress lines render into (inst/www/agent.js); in every chat
# footer, next to the interaction card. inst/www/interaction.js floats both
# above the composer.
.tool_progress_ui <- function()
  htmltools::div(id = "ca_tool_progress", class = "ca-tool-progress", `aria-live` = "polite")

# Clear every progress line of the session (end of a turn).
.progress_clear <- function(session) {
  if (is.null(session)) return(invisible(FALSE))
  tryCatch(session$sendCustomMessage("ca_tool_progress", list(action = "clear")), error = function(e) NULL)
  invisible(TRUE)
}
