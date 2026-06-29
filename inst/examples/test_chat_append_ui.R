#!/usr/bin/env Rscript
# inst/examples/test_chat_append_ui.R
#
# Demonstrate chat_append() with interactive UI elements embedded in messages.
#
# Run with:  shiny::runApp("inst/examples/test_chat_append_ui.R")

library(shiny)
library(bslib)
library(shinychat)
library(htmltools)

ui <- page_fillable(
  chat_ui(
    "chat",
    fill     = TRUE,
    greeting = "Send any message to see interactive UI embedded in responses."
  )
)

server <- function(input, output, session) {

  demo_counter <- reactiveVal(0L)

  observeEvent(input$chat_user_input, {
    req(nzchar(trimws(input$chat_user_input)))
    n <- demo_counter() + 1L
    demo_counter(n)

    # 1. Plain markdown echo
    chat_append("chat",
      paste0("You said: **", input$chat_user_input, "**\n\n---"),
      session = session
    )

    # 2. Embedded selectInput + actionButton
    chat_append("chat",
      tagList(
        tags$p(tags$strong(paste0("Demo #", n, ": interactive widget in chat bubble"))),
        tags$div(
          style = "display:flex; flex-direction:column; gap:8px; max-width:320px;",
          selectInput(
            paste0("demo_select_", n),
            label   = "Choose an option:",
            choices = c("Option A", "Option B", "Option C"),
            width   = "100%"
          ),
          actionButton(
            paste0("demo_confirm_", n),
            label = "Confirm",
            class = "btn-primary btn-sm",
            width = "100%"
          )
        )
      ),
      session = session
    )

    # 3. Observe the button dynamically
    local({
      idx <- n
      observeEvent(input[[paste0("demo_confirm_", idx)]], {
        sel <- input[[paste0("demo_select_", idx)]]
        chat_append("chat",
          paste0("You confirmed: **", sel, "**"),
          session = session
        )
      })
    })
  })

  # 4. A pre-populated message at startup using messages= (shown via greeting workaround)
  #    To truly pre-populate, pass messages= to chat_ui:
  #    chat_ui("chat", messages = list(
  #      list(role = "assistant", content = tagList(p("Hello!"), actionButton("x","Click me")))
  #    ))
}

shinyApp(ui, server)
