# inst/examples/test_shiny_ask_fn.R
# Phase 3 test app (v3): promise as pause signal, all UI updates in observers.
#
# Root cause of v1/v2 failures:
#   v1: later::run_now() -- Shiny reactive graph is non-reentrant, blocks.
#   v2: promises::then() callbacks run in later queue with NULL reactive domain
#       -> cannot write state$ or update UI from then().
#
# v3 solution: promise is ONLY a pause/resume mechanism.
#   - promise holds resolve/reject in state$pending_approval$resolve
#   - Allow/Deny observers call resolve() directly (correct reactive domain)
#   - All UI updates (log, chat_append) happen INSIDE the observers
#   - No then() needed -- observers are the "continuation"
#
# Run:
#   devtools::load_all()
#   shiny::runApp(
#     "inst/examples/test_shiny_ask_fn.R",
#     host = "0.0.0.0", port = 8080
#   )

library(shiny)
library(bslib)
library(shinychat)
library(promises)

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
      width = 240,
      tags$h6("Test controls"),
      actionButton("trigger_approval", "Trigger approval",
                   class = "btn-warning btn-sm w-100 mb-2"),
      actionButton("trigger_question", "Trigger question",
                   class = "btn-info btn-sm w-100 mb-2"),
      tags$hr(),
      tags$small("Log (newest last):"),
      verbatimTextOutput("log_out", placeholder = TRUE)
    ),
    card(
      card_header("Phase 3 ask_fn test (v3: promise as pause signal)"),
      # Approval and question bars sit just above the chat input area.
      # Using a flex column so bars push chat up naturally (no absolute positioning).
      chat_ui("chat", fill = TRUE,
              placeholder = "Type to echo (no LLM)",
              footer = tagList(
                uiOutput("ca_approval_ui"),
                uiOutput("ca_question_ui")
              ))
    )
  )
)

# ---------------------------------------------------------------------------
# Server
# ---------------------------------------------------------------------------

server <- function(input, output, session) {

  state <- reactiveValues(
    pending_approval = NULL,   # list(tool_name, tool_input, resolve)
    pending_question = NULL,   # list(question, choices, resolve)
    log              = character(0)
  )

  .log <- function(msg) {
    state$log <- c(state$log, paste0(format(Sys.time(), "%H:%M:%S"), " ", msg))
  }

  # ---- Chat echo ----
  observeEvent(input$chat_user_input, {
    val  <- input$chat_user_input
    text <- if (is.list(val)) val$text %||% "" else as.character(val)
    chat_append_message("chat",
      list(role = "assistant", content = paste0("Echo: ", text)),
      session = session)
  })

  # ---- Trigger approval ----
  observeEvent(input$trigger_approval, {
    cat("[DEBUG] trigger_approval clicked\n")
    .log("Waiting for approval of Bash(echo hello)...")
    # NOTE: keep the promise off the observer's return value. If `promise(...)`
    # is the last expression, observeEvent becomes an ASYNC observer and Shiny
    # keeps the reactive flush open until the promise settles. This pause-promise
    # only resolves on Allow/Deny, so the flush never completes and the freshly
    # rendered approval bar is never sent to the browser (stuck "recalculating").
    # Assign to a throwaway var and end with invisible(NULL) so the observer
    # completes synchronously and the UI renders immediately.
    .pr <- promise(function(resolve, reject) {
      cat("[DEBUG] promise executor running, setting pending_approval\n")
      state$pending_approval <- list(
        tool_name  = "Bash",
        tool_input = list(command = "echo hello"),
        resolve    = resolve
      )
      cat("[DEBUG] pending_approval set:", !is.null(isolate(state$pending_approval)), "\n")
    })
    cat("[DEBUG] trigger_approval handler done\n")
    invisible(NULL)
  })

  # ---- Trigger question ----
  observeEvent(input$trigger_question, {
    cat("[DEBUG] trigger_question clicked\n")
    .log("Waiting for answer to question...")
    # See trigger_approval note: never return the pause-promise from the observer,
    # or the reactive flush stalls and the question bar never renders.
    .pr <- promise(function(resolve, reject) {
      cat("[DEBUG] question promise executor, setting pending_question\n")
      state$pending_question <- list(
        question = "Which R package do you prefer?",
        choices  = c("ellmer", "btw", "shinychat"),
        resolve  = resolve
      )
    })
    invisible(NULL)
  })

  # ---- ESC: cancel pending ----
  observeEvent(input$esc, {
    pending_a <- isolate(state$pending_approval)
    pending_q <- isolate(state$pending_question)
    if (!is.null(pending_a)) {
      state$pending_approval <- NULL
      tryCatch(pending_a$resolve(FALSE), error = function(e) NULL)
      .log("ESC: approval cancelled")
    }
    if (!is.null(pending_q)) {
      state$pending_question <- NULL
      tryCatch(pending_q$resolve(""), error = function(e) NULL)
      .log("ESC: question cancelled")
    }
  })

  # ---- Approval bar ----
  output$ca_approval_ui <- renderUI({
    pending <- state$pending_approval
    cat("[DEBUG] ca_approval_ui rendering, pending =", !is.null(pending), "\n")
    if (is.null(pending)) return(NULL)
    div(
      style = paste(
        "border-top:2px solid var(--bs-warning,#f0ad4e);",
        "background:var(--bs-body-bg,#fff);",
        "padding:8px 16px; display:flex; align-items:center; gap:12px; text-align:left;",
        "box-shadow:0 -2px 8px rgba(0,0,0,.08);"
      ),
      tags$span(
        style = "font-weight:600; flex:1; font-size:0.9em;",
        "⚠️ Allow tool: ", tags$code(pending$tool_name),
        tags$small(
          style = "color:#666; font-weight:400;",
          paste0(" — ", substr(as.character(
            pending$tool_input$command %||% pending$tool_input$file_path %||% ""),
            1L, 80L))
        )
      ),
      actionButton("ca_tool_allow", "✔ Allow", class = "btn-success btn-sm"),
      actionButton("ca_tool_deny",  "✖ Deny",  class = "btn-danger btn-sm")
    )
  })

  # ---- Question bar ----
  output$ca_question_ui <- renderUI({
    pending <- state$pending_question
    cat("[DEBUG] ca_question_ui rendering, pending =", !is.null(pending), "\n")
    if (is.null(pending)) return(NULL)
    choices <- pending$choices
    div(
      style = paste(
        "border-top:2px solid var(--bs-info,#0dcaf0);",
        "background:var(--bs-body-bg,#fff);",
        "padding:8px 16px; text-align:left;",  # footer sets text-align:center; override it
        "box-shadow:0 -2px 8px rgba(0,0,0,.08);"
      ),
      tags$p(style = "font-weight:600; margin-bottom:6px;",
             "❓ ", pending$question),
      if (length(choices) > 0L)
        radioButtons("ca_q_choice", NULL, choices = choices, inline = FALSE)
      else
        textInput("ca_q_text", NULL, placeholder = "Type your answer..."),
      actionButton("ca_q_submit", "Submit", class = "btn-primary btn-sm")
    )
  })

  # ---- Allow observer: runs in correct reactive domain, does all side effects ----
  observeEvent(input$ca_tool_allow, ignoreNULL = TRUE, {
    cat("[DEBUG] ca_tool_allow clicked, input value:", input$ca_tool_allow, "\n")
    pending <- isolate(state$pending_approval)
    cat("[DEBUG] pending is NULL:", is.null(pending), "\n")
    if (is.null(pending)) return()
    state$pending_approval <- NULL
    tryCatch(pending$resolve(TRUE), error = function(e) NULL)
    .log(paste0("Allowed: ", pending$tool_name))
    chat_append_message("chat",
      list(role = "assistant", content = "✅ Tool allowed."),
      session = session)
  })

  # ---- Deny observer ----
  observeEvent(input$ca_tool_deny, ignoreNULL = TRUE, {
    cat("[DEBUG] ca_tool_deny clicked\n")
    pending <- isolate(state$pending_approval)
    if (is.null(pending)) return()
    state$pending_approval <- NULL
    tryCatch(pending$resolve(FALSE), error = function(e) NULL)
    .log(paste0("Denied: ", pending$tool_name))
    chat_append_message("chat",
      list(role = "assistant", content = "❌ Tool denied."),
      session = session)
  })

  # ---- Submit observer ----
  observeEvent(input$ca_q_submit, ignoreNULL = TRUE, {
    cat("[DEBUG] ca_q_submit clicked\n")
    pending <- isolate(state$pending_question)
    if (is.null(pending)) return()
    answer <- input$ca_q_choice %||% input$ca_q_text %||% ""
    state$pending_question <- NULL
    tryCatch(pending$resolve(answer), error = function(e) NULL)
    .log(paste0("Answer: ", answer))
    chat_append_message("chat",
      list(role = "assistant",
           content = paste0("ℹ️ Answer: **", answer, "**")),
      session = session)
  })

  # ---- Log ----
  output$log_out <- renderText({
    paste(tail(state$log, 20L), collapse = "\n")
  })
}

shinyApp(ui, server, br)
