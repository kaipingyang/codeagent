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
#'   `(question, choices, questions = NULL)` instead of `readline()`. Used by
#'   the Shiny UI to show an input bar and await the user's answer: a string
#'   for a single question, a list with one answer (character) per question
#'   for `questions`.
#' @param async Logical. When `TRUE`, the tool `fun` is a `coro::async`
#'   function that `await()`s a promise returned by `ask_question_fn` (Shiny
#'   path). Requires the chat to be run via `stream_async()`/`chat_async()`.
#'   Leave `FALSE` for the synchronous CLI path (an async fun always returns a
#'   promise, which the sync tool loop would not await).
#' @return An `ellmer::ToolDef`.
#' @export
ask_user_tool <- function(ask_question_fn = NULL, async = FALSE) {
  force(ask_question_fn)
  force(async)

  fun <- if (isTRUE(async)) {
    # coro cannot assign the result of an `if` expression, so branch with
    # side-effecting assignments instead of `answer <- if (...) ... else ...`.
    coro::async(function(question = NULL, choices = NULL, questions = NULL, `_intent` = NULL) {
      qs <- NULL
      if (!is.null(questions)) qs <- .normalize_questions(questions)
      if (is.null(qs) && !nzchar(as.character(question %||% "")))
        stop("AskUserQuestion needs `question` or `questions`.", call. = FALSE)
      ans <- ask_question_fn(question, choices, questions = qs)
      if (inherits(ans, "promise")) {
        answer <- await(ans)
      } else {
        answer <- ans
      }
      if (!is.null(qs)) return(.questions_tool_result(qs, answer))
      .ask_tool_result(as.character(answer %||% ""), question)
    })
  } else {
    function(question = NULL, choices = NULL, questions = NULL, `_intent` = NULL) {
      qs <- if (!is.null(questions)) .normalize_questions(questions)
      .ask_user_impl(question, choices, ask_question_fn, questions = qs)
    }
  }

  ellmer::tool(
    name = "AskUserQuestion",
    fun  = fun,
    description = paste0(
      "Ask the user questions and wait for their answers before continuing. ",
      "Use it to gather preferences or requirements, to clarify an ambiguous ",
      "instruction, or to let the user choose between approaches. Ask 1-4 ",
      "questions at once with `questions`; each has a short `header` (a chip of ",
      "at most 12 characters), 2-4 `options` (a concise `label` and an optional ",
      "`description` of what it means) and `multiSelect` (TRUE when several ",
      "options may apply). Users can always pick \"Other\" and type their own ",
      "answer, so do not add an Other option. If you recommend an option, list ",
      "it first and add \"(Recommended)\" to its label. The simple form ",
      "`question` (+ optional `choices`) asks one question. ",
      "Do NOT use for permission requests -- those are handled automatically."
    ),
    arguments = list(
      question = ellmer::type_string(
        "One question (simple form). Use `questions` for several or multiSelect.",
        required = FALSE),
      choices  = ellmer::type_array(
        "Optional list of choices for `question`. If provided, the user picks one.",
        items    = ellmer::type_string("A choice option."),
        required = FALSE),
      questions = ellmer::type_array(
        "1-4 questions to ask at once.",
        items = ellmer::type_object(
          question = ellmer::type_string("The complete question, ending with a question mark."),
          header = ellmer::type_string("Very short label shown as a chip (at most 12 characters).",
                                       required = FALSE),
          options = ellmer::type_array(
            "2-4 options; \"Other\" is added automatically.",
            items = ellmer::type_object(
              label = ellmer::type_string("Display text of the option (1-5 words)."),
              description = ellmer::type_string("What the option means.", required = FALSE))),
          multiSelect = ellmer::type_boolean("Allow several options to be selected.",
                                             required = FALSE)),
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

.ask_user_impl <- function(question, choices, ask_question_fn, questions = NULL) {
  if (!is.null(questions)) return(.ask_questions_impl(questions, ask_question_fn))
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
  .artifact_tool_result(
    if (nzchar(answer)) answer else "(no answer)",
    kind     = "text",
    icon     = "message-circle",
    title    = htmltools::HTML(sprintf(
      "<code>AskUserQuestion</code> -- %s",
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
#' @param async Logical. Build the async (promise-awaiting) variant (Shiny).
#' @return Invisibly `chat`.
#' @export
register_ask_user_tool <- function(chat, ask_question_fn = NULL, async = FALSE) {
  chat$register_tool(ask_user_tool(ask_question_fn, async = async))
  invisible(chat)
}

# ---------------------------------------------------------------------------
# Several questions (`questions`): option descriptions, multiSelect, Other
# ---------------------------------------------------------------------------

# Questions as the model sent them -- a list of objects, or the data frame
# ellmer may make of an array of objects (options then a list column of data
# frames) -- as a list of list(question, header, options = list(list(label,
# description)), multiSelect). Errors name what is wrong.
.normalize_questions <- function(questions) {
  rows <- if (is.data.frame(questions))
    lapply(seq_len(nrow(questions)), function(i) lapply(questions, function(col) col[[i]]))
  else questions
  if (!is.list(rows) || !length(rows) || length(rows) > 4L)
    stop("`questions` must hold 1 to 4 questions.", call. = FALSE)
  lapply(seq_along(rows), function(i) {
    q <- rows[[i]]
    text <- trimws(as.character(q$question %||% "")[1])
    if (is.na(text) || !nzchar(text)) stop("Question ", i, ": `question` is empty.", call. = FALSE)
    opts <- q$options
    opts <- if (is.data.frame(opts)) lapply(seq_len(nrow(opts)), function(j) lapply(opts, function(col) col[[j]]))
            else if (is.character(opts)) lapply(opts, function(x) list(label = x)) else opts
    opts <- lapply(opts %||% list(), function(o) {
      lab <- trimws(as.character(o$label %||% "")[1])
      desc <- as.character(o$description %||% "")[1]
      list(label = lab, description = if (is.na(desc)) "" else desc)
    })
    opts <- Filter(function(o) !is.na(o$label) && nzchar(o$label), opts)
    if (length(opts) < 2L)
      stop("Question ", i, " (", text, "): give at least 2 options.", call. = FALSE)
    hdr <- as.character(q$header %||% "")[1]
    list(question = text, header = if (is.na(hdr)) "" else substr(hdr, 1L, 12L),
         options = opts, multiSelect = isTRUE(as.logical(q$multiSelect %||% FALSE)))
  })
}

# What the model reads: every question with its answer.
.questions_answer_text <- function(questions, answers) {
  if (!length(answers)) return("The user dismissed the questions without answering.")
  pairs <- vapply(seq_along(questions), function(i) {
    a <- as.character(unlist(answers[i]))
    a <- a[!is.na(a) & nzchar(a)]
    sprintf("\"%s\"=\"%s\"", questions[[i]]$question, if (length(a)) paste(a, collapse = ", ") else "(no answer)")
  }, character(1L))
  paste0("The user answered your questions: ", paste(pairs, collapse = ", "),
         ". Continue with these answers in mind.")
}

.questions_tool_result <- function(questions, answers) {
  txt <- .questions_answer_text(questions, answers)
  .artifact_tool_result(
    txt, kind = "text", icon = "message-circle",
    title = htmltools::HTML(sprintf("<code>AskUserQuestion</code> -- %s",
      htmltools::htmlEscape(substr(questions[[1]]$question, 1L, 80L)))),
    payload = list(text = txt))
}

# One raw answer (option number(s), comma-separated for multiSelect, or free
# text = "Other") to the answer for that question.
.resolve_question_answer <- function(raw, q) {
  raw <- trimws(as.character(raw %||% ""))
  if (!nzchar(raw)) return(character())
  labels <- vapply(q$options, `[[`, "", "label")
  parts <- trimws(strsplit(raw, ",", fixed = TRUE)[[1]])
  idx <- suppressWarnings(as.integer(parts))
  if (all(!is.na(idx)) && all(idx >= 1L & idx <= length(labels)))
    return(if (isTRUE(q$multiSelect)) labels[idx] else labels[idx[1L]])
  raw
}

.ask_questions_impl <- function(questions, ask_question_fn) {
  if (is.function(ask_question_fn)) {
    answers <- tryCatch(ask_question_fn(NULL, NULL, questions = questions), error = function(e) list())
    return(.questions_tool_result(questions, answers))
  }
  test_ans <- getOption("codeagent.test_ask_answer", default = NULL)
  if (!is.null(test_ans)) {
    test_ans <- rep_len(as.character(test_ans), length(questions))
    return(.questions_tool_result(questions,
      lapply(seq_along(questions), function(i) .resolve_question_answer(test_ans[i], questions[[i]]))))
  }
  if (!interactive()) {
    cli::cli_alert_warning("AskUserQuestion called in non-interactive session. Returning no answers.")
    return(.questions_tool_result(questions, list()))
  }
  answers <- lapply(questions, function(q) {
    cli::cli_text("{.strong {q$question}}")
    for (i in seq_along(q$options))
      cli::cli_text("  {i}. {q$options[[i]]$label}{if (nzchar(q$options[[i]]$description)) paste0(' -- ', q$options[[i]]$description) else ''}")
    cli::cli_text(if (isTRUE(q$multiSelect)) "Enter numbers separated by commas, or type your answer: "
                  else "Enter a number or type your answer: ")
    .resolve_question_answer(readline(""), q)
  })
  .questions_tool_result(questions, answers)
}
