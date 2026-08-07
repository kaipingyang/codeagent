#' @title Output Gate --- the edge-3 counterpart of the input gate
#' @description Data Shield guards three edges into/out of the model:
#'   * **edge 1** input gate (`R/input_gate.R`): user input BEFORE the model.
#'   * **edge 2** tool gate (`R/tools_gate.R`): tool traffic in/out of the model.
#'   * **edge 3** output gate (this file): the model's final reply BEFORE it
#'     reaches the user.
#'
#'   The output gate closes the last confidentiality gap: the model may
#'   reproduce a protected value it inferred from tool output (an edge-2
#'   aggregate the shield let through) even when the user's own input was clean.
#'   Symmetric to the input gate, it reuses the shield's `scan_response()` (a
#'   thin wrapper over `scan_prompt()` --- identical value_match + PII detectors,
#'   audited under `edge = "response"`).
#'
#'   **Streaming constraint (Shiny):** `shinychat::chat_append("chat", stream)`
#'   renders the reply token-by-token straight to the browser, so there is no
#'   "finalize then intercept" point --- the text is already on screen. The
#'   Shiny caller therefore scans the finished reply AFTER the stream completes
#'   and APPENDS a warning message below (never redacts in place; the plaintext
#'   was already shown). The CLI path is non-streaming: `agent_loop` holds the
#'   full `response` string and CAN redact it before returning.
#' @name output_gate
#' @keywords internal
NULL

#' Run the Data Shield output gate on the model's final reply.
#'
#' Call this AFTER the model's reply is finalized, BEFORE returning it to the
#' user (CLI) or as a post-stream check (Shiny). No-op when no shield is active.
#'
#' @param text Character scalar. The model's final reply.
#' @param settings The agent settings list (`data_shield_engine`,
#'   `data_shield_response_on_fail`, `data_shield_output_scanners`).
#' @param chat The ellmer Chat (fallback shield source via attribute).
#' @param on_progress Optional progress callback forwarded to `scan_response()`.
#' @return A list: `action` (`"pass"`/`"redact"`/`"block"`), `text` (the
#'   possibly-redacted reply), and `matches` (count). When no shield is active,
#'   returns `list(action = "pass", text = text)`.
#' @keywords internal
.output_gate_scan <- function(text, settings = list(), chat = NULL,
                              on_progress = NULL) {
  shield <- .input_gate_shield(settings, chat)   # reuse edge-1 resolver
  if (is.null(shield)) return(list(action = "pass", text = text))
  if (!is.character(text) || length(text) != 1L || !nzchar(text))
    return(list(action = "pass", text = text))
  on_fail  <- settings$data_shield_response_on_fail %||% "redact"
  scanners <- settings$data_shield_output_scanners %||% c("value_match", "regex")
  r <- tryCatch(
    shield$scan_response(text, on_fail = on_fail, scanners = scanners,
                         on_progress = on_progress),
    error = function(e) list(action = "pass", text = text, matches = 0L))
  # "ask" has no wired approval path on the output side (the reply is already
  # produced); fail safe to redact-and-return, never surface unscanned text.
  if (identical(r$action, "ask")) {
    redacted <- tryCatch(
      shield$scan_response(text, on_fail = "redact", scanners = scanners),
      error = function(e) list(action = "pass", text = text))
    return(list(action = "redact", text = redacted$text %||% text,
                matches = redacted$matches %||% 0L))
  }
  list(action = r$action %||% "pass", text = r$text %||% text,
       matches = r$matches %||% 0L)
}
