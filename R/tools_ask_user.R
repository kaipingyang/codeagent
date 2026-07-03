#' @title AskUserQuestion Tool
#' @description Lets the LLM pause the agentic loop and ask the user a
#'   clarifying question, waiting for their answer before continuing.
#'   Available in all permission modes (read-only, no side effects).
#'
#'   - **CLI path**: uses `readline()` (or `getOption("codeagent.test_ask_answer")`
#'     for tests/non-interactive fallback).
#'   - **Shiny path**: delegates to an injected `ask_question_fn` callback that
#'     shows an input bar and resolves asynchronously (Phase 3).
#' @name tools_ask_user
#' @keywords internal
NULL

#' Create the AskUserQuestion tool
#'
#' @param ask_question_fn Function or NULL. If provided, called with
#'   `(question, choices)` instead of `readline()`. Used by the Shiny UI
#'   to show an input bar and await the user's answer.
#' @return An `ellmer::ToolDef`.
#' @export
ask_user_tool <- function(ask_question_fn = NULL) {
  force(ask_question_fn)

  ellmer::tool(
    name = "AskUserQuestion",
    fun  = function(question, choices = NULL, `_intent` = NULL) {
      .ask_user_impl(question, choices, ask_question_fn)
    },
    description = paste0(
      "Ask the user a clarifying question and wait for their answer before ",
      "continuing. Use when you need information from the user to proceed ",
      "(e.g. which file to modify, which approach to take). ",
      "Do NOT use for permission requests -- those are handled automatically."
    ),
    arguments = list(
      question = ellmer::type_string(
        "The question to ask the user.", required = TRUE),
      choices  = ellmer::type_array(
        "Optional list of choices. If provided, the user picks one.",
        items    = ellmer::type_string("A choice option."),
        required = FALSE),
      `_intent` = ellmer::type_string(
        "Brief description of why the question is needed.", required = FALSE)
    ),
    annotations = ellmer::tool_annotations(
      title          = "AskUserQuestion",
      read_only_hint = TRUE
    )
  )
}

# ---------------------------------------------------------------------------
# Core implementation: CLI path + test/non-interactive fallback
# ---------------------------------------------------------------------------

.ask_user_impl <- function(question, choices, ask_question_fn) {
  # Shiny path: delegate to injected callback (Phase 3)
  if (is.function(ask_question_fn)) {
    answer <- tryCatch(
      ask_question_fn(question, choices),
      error = function(e) ""
    )
    return(.ask_tool_result(answer, question))
  }

  # Test/non-interactive override: getOption("codeagent.test_ask_answer")
  test_ans <- getOption("codeagent.test_ask_answer", default = NULL)
  if (!is.null(test_ans)) {
    answer <- .resolve_answer(as.character(test_ans), choices)
    return(.ask_tool_result(answer, question))
  }

  # Non-interactive guard: do not hang in scripts/CI
  if (!interactive()) {
    msg <- paste0("[AskUserQuestion skipped -- non-interactive session] ", question)
    cli::cli_alert_warning(
      "AskUserQuestion called in non-interactive session. Returning empty answer.")
    return(.ask_tool_result("", question))
  }

  # Interactive CLI path
  .ask_user_cli(question, choices)
}

.ask_user_cli <- function(question, choices) {
  if (length(choices) > 0L) {
    cli::cli_text("{.strong {question}}")
    for (i in seq_along(choices)) {
      cli::cli_text("  {i}. {choices[[i]]}")
    }
    cli::cli_text("Enter number or type your answer: ")
    raw <- trimws(readline(""))
  } else {
    raw <- trimws(readline(paste0(question, " ")))
  }
  answer <- .resolve_answer(raw, choices)
  .ask_tool_result(answer, question)
}

# Resolve raw input: if choices given and input is a valid index, return the
# corresponding choice; otherwise return the raw string.
.resolve_answer <- function(raw, choices) {
  if (length(choices) > 0L && nzchar(raw)) {
    idx <- suppressWarnings(as.integer(raw))
    if (!is.na(idx) && idx >= 1L && idx <= length(choices)) {
      return(choices[[idx]])
    }
  }
  raw
}

.ask_tool_result <- function(answer, question) {
  .tool_result2(
    if (nzchar(answer)) answer else "(no answer)",
    kind     = "text",
    icon     = "message-circle",
    title    = htmltools::HTML(sprintf(
      "<code>AskUserQuestion</code> — %s",
      htmltools::htmlEscape(substr(question, 1L, 80L))
    )),
    payload  = list(text = answer)
  )
}

# ---------------------------------------------------------------------------
# Registration
# ---------------------------------------------------------------------------

#' Register the AskUserQuestion tool on a Chat
#'
#' @param chat An `ellmer::Chat` object.
#' @param ask_question_fn Function or NULL. Shiny callback for Phase 3.
#' @return Invisibly `chat`.
#' @export
register_ask_user_tool <- function(chat, ask_question_fn = NULL) {
  chat$register_tool(ask_user_tool(ask_question_fn))
  invisible(chat)
}
