#' @title Prompt Gate --- the edge-1 counterpart of the tool gate
#' @description The tool gate (`R/tools_gate.R`) guards edge 2 (tool traffic) by
#'   wrapping ellmer's `on_tool_request` / tool functions. The **prompt gate**
#'   guards edge 1: the user's message *before it reaches the model*. Unlike the
#'   tool gate it has no ellmer chat-level hook to attach to (user input is
#'   handled inside `agent_loop`, not inside the Chat object), so the prompt gate
#'   is a function the agent loop calls at the UserPromptSubmit point.
#'
#'   Two consumers run at this edge, in order (mirroring the tool gate's
#'   hooks-then-shield layering), kept as SEPARATE systems:
#'   1. **hooks** `run_user_prompt_submit()` -- aligns with Claude Code's
#'      `UserPromptSubmit`; may `block` or append context, NEVER redacts
#'      (handled in `agent_loop` directly).
#'   2. **Data Shield** `scan_prompt()` -- the shield's own confidentiality
#'      scan; MAY redact (protected values / PII the user pasted in). This file
#'      wires that second consumer.
#' @name prompt_gate
#' @keywords internal
NULL

#' Run the Data Shield prompt gate on a user message.
#'
#' Call this in the agent loop AFTER the UserPromptSubmit hook, BEFORE the
#' prompt is sent to the model. It resolves the active shield the same way the
#' tool gate does (settings engine first, then the chat attribute) and applies
#' `scan_prompt()`.
#'
#' @param user_input Character scalar. The raw user prompt (post-hook).
#' @param settings The agent settings list (for `data_shield_engine`).
#' @param chat The ellmer Chat (fallback shield source via attribute).
#' @param on_progress Optional progress callback forwarded to `scan_prompt()`.
#' @return A list: `action` (`"pass"`/`"redact"`/`"block"`/`"ask"`) and `text`
#'   (possibly redacted prompt). `"pass"`/`"redact"` mean "continue with `text`";
#'   `"block"` means "reject this turn"; `"ask"` currently degrades to redact at
#'   this call site unless the caller wires an approval path. When no shield is
#'   active, returns `list(action = "pass", text = user_input)`.
#' @keywords internal
.prompt_gate_scan <- function(user_input, settings = list(), chat = NULL,
                              on_progress = NULL) {
  if (!is.character(user_input) || length(user_input) != 1L || !nzchar(user_input))
    return(list(action = "pass", text = user_input))
  shield <- settings$data_shield_engine %||%
    tryCatch(attr(chat, "codeagent_data_shield"), error = function(e) NULL)
  if (is.null(shield) || !inherits(shield, "DataShield"))
    return(list(action = "pass", text = user_input))

  on_fail <- settings$data_shield_prompt_on_fail %||% "redact"
  res <- tryCatch(
    shield$scan_prompt(user_input, on_fail = on_fail, on_progress = on_progress),
    error = function(e) list(action = "pass", text = user_input, matches = 0L))

  # "ask" without a wired approval path fails safe to redact-and-continue: we
  # never send the un-scanned text to the model on an unresolved ask.
  if (identical(res$action, "ask")) {
    redacted <- tryCatch(
      shield$scan_prompt(user_input, on_fail = "redact", on_progress = NULL),
      error = function(e) list(action = "pass", text = user_input))
    return(list(action = "redact", text = redacted$text %||% user_input))
  }
  list(action = res$action %||% "pass", text = res$text %||% user_input)
}
