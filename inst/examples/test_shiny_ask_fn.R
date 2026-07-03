# inst/examples/test_shiny_ask_fn.R
# Phase 3 test app: verify later::run_now() pump mechanism for Shiny ask_fn.
#
# Tests:
#   - Tool approval bar: Allow / Deny buttons inline under chat
#   - AskUserQuestion bar: text input + submit
#   - ESC interrupt during wait (no deadlock)
#
# This app uses a FAKE tool that immediately triggers approval/question
# (no LLM call needed) so the mechanism can be tested without an API key.
#
# Run:
#   shiny::runApp(
#     "inst/examples/test_shiny_ask_fn.R",
#     host = "0.0.0.0", port = 8080
#   )
#
# Manual tests:
#   1. Click "Trigger approval" → approval bar appears → Allow/Deny works
#   2. Click "Trigger question" → question bar appears → answer submits
#   3. Click "Trigger approval" then ESC → no deadlock, bar disappears

library(shiny)
library(bslib)
library(shinychat)
library(later)
library(promises)

# ---------------------------------------------------------------------------
# Shared pump mechanism prototype
# ---------------------------------------------------------------------------

# .shiny_ask_fn_proto: synchronous ask_fn that pumps later queue while waiting
# for user interaction. Uses state$pending_approval reactiveVal.
# Returns TRUE (allow) or FALSE (deny).

.shiny_ask_fn_proto <- function(session, state) {
  function(tool_name, tool_input) {
    signal <- new.env(parent = emptyenv())
    signal$done  <- FALSE
    signal$value <- FALSE

    shiny::isolate(state$pending_approval <- list(
      tool_name  = tool_name,
      tool_input = tool_input,
      resolve    = function(ok) {
        signal$value <- isTRUE(ok)
        signal$done  <- TRUE
      }
    ))

    # Pump event loop until Allow/Deny observer resolves the signal,
    # or interrupt flag is set (ESC), or timeout (60s safety net).
    deadline <- proc.time()[["elapsed"]] + 60
    while (!signal$done) {
      later::run_now(timeout = 0.05)
      if (isTRUE(shiny::isolate(state$interrupt))) break
      if (proc.time()[["elapsed"]] > deadline) break
    }

    shiny::isolate(state$pending_approval <- NULL)
    isTRUE(signal$value)
  }
}

# .shiny_ask_question_proto: same pattern for AskUserQuestion
.shiny_ask_question_proto <- function(session, state) {
  function(question, choices) {
    signal <- new.env(parent = emptyenv())
    signal$done   <- FALSE
    signal$answer <- ""

    shiny::isolate(state$pending_question <- list(
      question = question,
      choices  = choices,
      resolve  = function(answer) {
        signal$answer <- as.character(answer)
        signal$done   <- TRUE
      }
    ))

    deadline <- proc.time()[["elapsed"]] + 120
    while (!signal$done) {
      later::run_now(timeout = 0.05)
      if (isTRUE(shiny::isolate(state$interrupt))) break
      if (proc.time()[["elapsed"]] > deadline) break
    }

    shiny::isolate(state$pending_question <- NULL)
    signal$answer
  }
}

# ---------------------------------------------------------------------------
# UI
# ---------------------------------------------------------------------------

ui <- page_fillable(
  tags$script(HTML("
    document.addEventListener('keydown', function(e) {
      if (e.key === 'Escape') {
        Shiny.setInputValue('esc', Math.random(), {priority: 'event'});
      }
    });
  ")),
  layout_sidebar(
    sidebar = sidebar(
      width = 220,
      tags$h6("Test controls"),
      actionButton("trigger_approval", "Trigger approval",
                   class = "btn-warning btn-sm w-100 mb-2"),
      actionButton("trigger_question", "Trigger question",
                   class = "btn-info btn-sm w-100 mb-2"),
      tags$hr(),
      verbatimTextOutput("log_out", placeholder = TRUE)
    ),
    card(
      card_header("Phase 3 ask_fn pump test"),
      chat_ui("chat", fill = TRUE,
              placeholder = "Type anything to chat (no LLM, echo only)"),
      # Approval bar: renders when pending_approval is set
      uiOutput("ca_approval_ui"),
      # Question bar: renders when pending_question is set
      uiOutput("ca_question_ui")
    )
  )
)

# ---------------------------------------------------------------------------
# Server
# ---------------------------------------------------------------------------

server <- function(input, output, session) {

  state <- reactiveValues(
    interrupt        = FALSE,
    pending_approval = NULL,
    pending_question = NULL,
    log              = character(0)
  )

  .log <- function(msg) {
    state$log <- c(state$log, paste0(format(Sys.time(), "%H:%M:%S"), " ", msg))
  }

  # Construct callbacks
  ask_fn          <- .shiny_ask_fn_proto(session, state)
  ask_question_fn <- .shiny_ask_question_proto(session, state)

  # ---- Chat echo (no LLM) ----
  observeEvent(input$chat_user_input, {
    val <- input$chat_user_input
    text <- if (is.list(val)) val$text %||% "" else as.character(val)
    chat_append_message("chat",
      list(role = "assistant",
           content = paste0("Echo: ", text)),
      session = session)
  })

  # ---- Trigger approval test ----
  observeEvent(input$trigger_approval, {
    .log("Triggering approval for Bash(echo hello)")
    # Run ask_fn in a promise so it doesn't block the observer itself
    # (the pump runs inside ask_fn, which IS called synchronously from here,
    # but the later:: pump will handle the Allow/Deny observers)
    result <- ask_fn("Bash", list(command = "echo hello"))
    .log(paste0("Approval result: ", if (result) "ALLOWED" else "DENIED"))
    chat_append_message("chat",
      list(role = "assistant",
           content = paste0("ℹ️ Approval: ", if (result) "✅ allowed" else "❌ denied")),
      session = session)
  })

  # ---- Trigger question test ----
  observeEvent(input$trigger_question, {
    .log("Triggering AskUserQuestion")
    answer <- ask_question_fn(
      "Which R package do you prefer?",
      c("ellmer", "btw", "shinychat")
    )
    .log(paste0("Answer: ", answer))
    chat_append_message("chat",
      list(role = "assistant",
           content = paste0("ℹ️ Answer received: **", answer, "**")),
      session = session)
  })

  # ---- ESC interrupt ----
  observeEvent(input$esc, {
    state$interrupt <- TRUE
    .log("ESC interrupt")
    later::later(function() state$interrupt <- FALSE, delay = 0.5)
  })

  # ---- Approval bar UI ----
  output$ca_approval_ui <- renderUI({
    pending <- state$pending_approval
    if (is.null(pending)) return(NULL)
    div(
      style = paste(
        "border-top: 2px solid #f0ad4e; background: #fff8f0;",
        "padding: 10px 16px; display: flex; align-items: center; gap: 12px;"
      ),
      tags$span(
        style = "font-weight:600; flex:1; font-size:0.9em;",
        "⚠️ Allow tool: ",
        tags$code(pending$tool_name),
        tags$small(style = "color:#666; font-weight:400;",
                   paste0(" — ", substr(as.character(
                     pending$tool_input$command %||% pending$tool_input$file_path %||% ""), 1, 80)))
      ),
      actionButton("ca_tool_allow", "✔ Allow", class = "btn-success btn-sm"),
      actionButton("ca_tool_deny",  "✖ Deny",  class = "btn-danger btn-sm")
    )
  })

  # ---- Question bar UI ----
  output$ca_question_ui <- renderUI({
    pending <- state$pending_question
    if (is.null(pending)) return(NULL)
    choices <- pending$choices
    div(
      style = paste(
        "border-top: 2px solid #0dcaf0; background: #f0faff;",
        "padding: 10px 16px;"
      ),
      tags$p(style = "font-weight:600; margin-bottom:6px;",
             "❓ ", pending$question),
      if (length(choices) > 0L)
        radioButtons("ca_q_choice", NULL, choices = choices, inline = TRUE)
      else
        textInput("ca_q_text", NULL, placeholder = "Type your answer..."),
      actionButton("ca_q_submit", "Submit", class = "btn-primary btn-sm")
    )
  })

  # ---- Allow / Deny observers ----
  observeEvent(input$ca_tool_allow, {
    pending <- isolate(state$pending_approval)
    if (!is.null(pending)) {
      pending$resolve(TRUE)
      .log("User clicked Allow")
    }
  })

  observeEvent(input$ca_tool_deny, {
    pending <- isolate(state$pending_approval)
    if (!is.null(pending)) {
      pending$resolve(FALSE)
      .log("User clicked Deny")
    }
  })

  # ---- Question submit observer ----
  observeEvent(input$ca_q_submit, {
    pending <- isolate(state$pending_question)
    if (!is.null(pending)) {
      answer <- if (!is.null(input$ca_q_choice)) input$ca_q_choice
                else input$ca_q_text %||% ""
      pending$resolve(answer)
      .log(paste0("User answered: ", answer))
    }
  })

  # ---- Log output ----
  output$log_out <- renderText({
    paste(tail(state$log, 15), collapse = "\n")
  })
}

shinyApp(ui, server)
