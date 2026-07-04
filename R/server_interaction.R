#' @title Shiny interaction pause mechanism (Phase 3)
#' @description Shared "pause -> wait for user -> resume" machinery for two
#'   features that ride the same promise-as-pause-signal design:
#'
#'   * **ask_fn** -- harness permission approval (Allow/Deny a risky tool).
#'   * **ask_question_fn** -- `AskUserQuestion` clarifying-question input.
#'
#'   Both store a single `state$pending_interaction` slot and expose an
#'   interaction bar in the chat footer. The promise returned by the ask
#'   functions is awaited by the (async) tool inside the streaming task; it is
#'   resolved by the Allow/Deny/Submit observers here.
#'
#'   Hard-won constraints (see `inst/examples/test_shiny_ask_fn.R`):
#'   * The promise is ONLY a container for `resolve`; never use `then()` to do
#'     UI side effects (then() runs with a NULL reactive domain).
#'   * All UI side effects happen inside the Allow/Deny/Submit observers, which
#'     run in the correct reactive domain.
#' @name server_interaction
#' @keywords internal
NULL

# Build the promise-returning ask_fn (permission approval). Called from inside
# an async tool; returns promise<logical>. resolve(TRUE/FALSE) is called by the
# Allow/Deny observers.
.shiny_ask_fn <- function(session, state) {
  function(tool_name, tool_input) {
    promises::promise(function(resolve, reject) {
      shiny::isolate({
        state$pending_interaction <- list(
          type    = "approval",
          payload = list(tool_name = tool_name, tool_input = tool_input),
          resolve = resolve
        )
      })
    })
  }
}

# Build the promise-returning ask_question_fn (AskUserQuestion). Returns
# promise<character>. resolve(answer) is called by the Submit observer.
.shiny_ask_question_fn <- function(session, state) {
  function(question, choices = NULL) {
    promises::promise(function(resolve, reject) {
      shiny::isolate({
        state$pending_interaction <- list(
          type    = "question",
          payload = list(question = question,
                         choices  = as.character(choices %||% character(0))),
          resolve = resolve
        )
      })
    })
  }
}

# Resolve + clear the pending interaction safely (idempotent).
.resolve_pending <- function(state, value) {
  pending <- shiny::isolate(state$pending_interaction)
  if (is.null(pending)) return(invisible(FALSE))
  state$pending_interaction <- NULL
  tryCatch(pending$resolve(value), error = function(e) NULL)
  invisible(TRUE)
}

#' Wire the interaction bar UI + observers into a Shiny session
#'
#' @param input,output,session Standard Shiny server args.
#' @param state The shared `reactiveValues` (must contain `pending_interaction`).
#' @return A list with `ask_fn` and `ask_question_fn` (promise-returning).
#' @keywords internal
server_interaction <- function(input, output, session, state) {

  # ---- Interaction bar (approval OR question) ----
  output$ca_interaction_ui <- shiny::renderUI({
    pending <- state$pending_interaction
    if (is.null(pending)) return(NULL)

    if (identical(pending$type, "approval")) {
      p    <- pending$payload
      tin  <- p$tool_input %||% list()
      desc <- as.character(tin$command %||% tin$file_path %||% "")
      htmltools::tags$div(
        style = paste(
          "border-top:2px solid var(--bs-warning,#f0ad4e);",
          "background:var(--bs-body-bg,#fff);",
          "padding:8px 16px; display:flex; align-items:center; gap:12px;",
          "text-align:left;",   # footer sets text-align:center; override it
          "box-shadow:0 -2px 8px rgba(0,0,0,.08);"
        ),
        htmltools::tags$span(
          style = "font-weight:600; flex:1; font-size:0.9em;",
          "\u26a0\ufe0f Allow tool: ", htmltools::tags$code(p$tool_name %||% "?"),
          htmltools::tags$small(
            style = "color:#666; font-weight:400;",
            if (nzchar(desc)) paste0(" \u2014 ", substr(desc, 1L, 80L)) else ""
          )
        ),
        shiny::actionButton("ca_tool_allow", "\u2714 Allow",
                            class = "btn-success btn-sm"),
        shiny::actionButton("ca_tool_deny", "\u2716 Deny",
                            class = "btn-danger btn-sm")
      )
    } else if (identical(pending$type, "question")) {
      p       <- pending$payload
      choices <- p$choices
      htmltools::tags$div(
        style = paste(
          "border-top:2px solid var(--bs-info,#0dcaf0);",
          "background:var(--bs-body-bg,#fff);",
          "padding:8px 16px; text-align:left;",   # override footer centering
          "box-shadow:0 -2px 8px rgba(0,0,0,.08);"
        ),
        htmltools::tags$p(style = "font-weight:600; margin-bottom:6px;",
                          "\u2753 ", p$question %||% ""),
        if (length(choices) > 0L)
          shiny::radioButtons("ca_q_choice", NULL, choices = choices,
                              inline = FALSE)
        else
          shiny::textInput("ca_q_text", NULL,
                           placeholder = "Type your answer..."),
        shiny::actionButton("ca_q_submit", "Submit", class = "btn-primary btn-sm")
      )
    } else {
      NULL
    }
  })

  # ---- Allow / Deny (permission approval) ----
  shiny::observeEvent(input$ca_tool_allow, ignoreInit = TRUE, {
    if (.resolve_pending(state, TRUE))
      shinychat::chat_append_message(
        "chat", list(role = "assistant", content = "\u2705 Tool allowed."),
        session = session)
  })
  shiny::observeEvent(input$ca_tool_deny, ignoreInit = TRUE, {
    if (.resolve_pending(state, FALSE))
      shinychat::chat_append_message(
        "chat", list(role = "assistant", content = "\u274c Tool denied."),
        session = session)
  })

  # ---- Submit (question answer) ----
  shiny::observeEvent(input$ca_q_submit, ignoreInit = TRUE, {
    pending <- shiny::isolate(state$pending_interaction)
    if (is.null(pending) || !identical(pending$type, "question")) return()
    answer <- input$ca_q_choice %||% input$ca_q_text %||% ""
    .resolve_pending(state, answer)
  })

  # ---- ESC: cancel a pending interaction without deadlocking the loop ----
  # Deny an approval (FALSE) or return an empty answer ("") for a question.
  shiny::observeEvent(input$esc, {
    pending <- shiny::isolate(state$pending_interaction)
    if (is.null(pending)) return()
    cancel_value <- if (identical(pending$type, "approval")) FALSE else ""
    .resolve_pending(state, cancel_value)
  })

  list(
    ask_fn          = .shiny_ask_fn(session, state),
    ask_question_fn = .shiny_ask_question_fn(session, state)
  )
}
