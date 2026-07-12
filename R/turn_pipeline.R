#' @title Turn pipeline helpers
#' @description
#'   Shared per-turn setup and teardown for console, Shiny, and ink frontends.
#'   Centralises: compaction, resource replacement, system-reminder injection,
#'   session save, and usage/cost reporting.
#' @name turn_pipeline
#' @keywords internal
NULL

# ---------------------------------------------------------------------------
# .inject_reminder_to_input
# ---------------------------------------------------------------------------
# Append a <system-reminder> block to the text portion of `input`.
# `input` can be:
#   - character scalar (CLI / ink)
#   - list (Shiny: text element + Content attachments)
# Returns the same type as input, with the reminder appended to the text part.
.inject_reminder_to_input <- function(input, reminder) {
  if (!nzchar(reminder %||% "")) return(input)
  if (is.character(input)) return(paste0(input, "\n\n", reminder))
  # list input: first element is the text string, rest are Content attachments
  if (is.list(input) && length(input) > 0L && is.character(input[[1L]])) {
    input[[1L]] <- paste0(input[[1L]], "\n\n", reminder)
    return(input)
  }
  input
}

# ---------------------------------------------------------------------------
# .turn_setup
# ---------------------------------------------------------------------------
#' Run per-turn setup: compaction, resource replacement, system-reminder injection.
#'
#' @param client A `CodeagentClient` or bare `ellmer::Chat`.
#' @param input Character scalar (CLI/ink) OR list (Shiny: text + attachments).
#' @param iteration Integer. Current loop iteration (1 = first).
#' @param cwd Character or NULL. Working directory.
#' @param compaction_ctrl A `CompactionController` or NULL.
#' @param resource_state A `ContentReplacementState` or NULL.
#' @return `input` with system-reminder injected (same type as input).
#' @keywords internal
.turn_setup <- function(client, input, iteration = 1L, cwd = NULL,
                         compaction_ctrl = NULL, resource_state = NULL) {
  chat     <- if (inherits(client, "CodeagentClient")) client$chat else client
  settings <- if (inherits(client, "CodeagentClient")) client$settings else list()
  if (is.null(cwd)) cwd <- settings$cwd %||% getwd()

  # Compaction (before sending the turn)
  if (!is.null(compaction_ctrl))
    tryCatch(
      compaction_ctrl$maybe_compact(
        chat,
        settings$model_limit %||% 200000L,
        compact_model = .resolve_compact_model(chat, settings)),
      error = function(e) NULL)

  # Resource replacement (snip old large tool results)
  if (!is.null(resource_state))
    tryCatch(resource_state$maybe_replace(chat), error = function(e) NULL)

  # system-reminder injection: extract text for the reminder query,
  # then inject back into the original input (preserving list shape).
  text_part <- if (is.list(input) && length(input) > 0L && is.character(input[[1L]]))
                 input[[1L]]
               else if (is.character(input))
                 input
               else ""

  reminder <- tryCatch(
    .build_system_reminder(settings, as.integer(iteration), cwd, query = text_part),
    error = function(e) "")

  .inject_reminder_to_input(input, reminder)
}

# ---------------------------------------------------------------------------
# .turn_teardown
# ---------------------------------------------------------------------------
#' Run per-turn teardown: save session and return usage + cost.
#'
#' @param client A `CodeagentClient` or bare `ellmer::Chat`.
#' @param cwd Character or NULL.
#' @param session_id Character or NULL.
#' @return Named list with elements:
#'   * `n_tokens`: integer token count (real or estimated)
#'   * `model_limit`: integer context window limit
#'   * `warning_state`: list from `calculate_token_warning_state()` or NULL
#'   * `cost_last`: numeric cost of the last turn in USD, or NA_real_
#' @keywords internal
.turn_teardown <- function(client, cwd = NULL, session_id = NULL) {
  chat     <- if (inherits(client, "CodeagentClient")) client$chat else client
  settings <- if (inherits(client, "CodeagentClient")) client$settings else list()
  if (is.null(cwd)) cwd <- settings$cwd %||% getwd()

  tryCatch(save_session(chat, cwd, session_id), error = function(e) NULL)

  n    <- tryCatch(token_count_with_estimation(chat), error = function(e) 0L)
  lim  <- settings$model_limit %||% 200000L
  ws   <- tryCatch(calculate_token_warning_state(n, settings$model %||% ""),
                   error = function(e) NULL)
  cost <- tryCatch(chat$get_cost(include = "last"), error = function(e) NA_real_)

  list(n_tokens = n, model_limit = lim, warning_state = ws, cost_last = cost)
}
