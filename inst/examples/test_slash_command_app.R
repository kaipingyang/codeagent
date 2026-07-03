# inst/examples/test_slash_command_app.R
# Test app: verify shinychat dev chat_server()$slash_command() API.
#
# Tests:
#   - /plan   (no args)
#   - /compact (no args)
#   - /rewind  (takes numeric arg via ContentSlashCommand@user_text)
#   - /clear   (no args, clears UI + client history)
#
# Run:
#   shiny::runApp("inst/examples/test_slash_command_app.R", host = "0.0.0.0", port = 8080)

library(shiny)
library(ellmer)
library(shinychat)

ui <- bslib::page_fillable(
  bslib::card(
    bslib::card_header("shinychat slash_command() test"),
    bslib::card_body(
      tags$p(
        tags$b("Instructions:"),
        " Type ", tags$code("/"), " in the chat input to see the slash palette.",
        " Registered commands: /plan, /compact, /rewind [n], /clear"
      )
    ),
    fill = FALSE
  ),
  shinychat::chat_ui("chat", fill = TRUE, allow_attachments = FALSE,
                     placeholder = "Type / to see slash commands...")
)

server <- function(input, output, session) {
  # Minimal chat client (OpenAI-compatible, bypass mode)
  chat <- tryCatch(
    ellmer::chat_openai_compatible(
      base_url    = Sys.getenv("CODEAGENT_BASE_URL"),
      model       = Sys.getenv("CODEAGENT_MODEL", "test"),
      credentials = function() Sys.getenv("CODEAGENT_API_KEY"),
      echo        = "none"
    ),
    error = function(e) {
      showNotification(paste("Chat init failed:", conditionMessage(e)), type = "error")
      NULL
    }
  )
  if (is.null(chat)) return()

  mod <- shinychat::chat_server("chat", chat, session = session)

  # /plan — no arguments
  mod$slash_command("plan", "Enter plan mode (read-only)", function() {
    mod$append("**Plan mode active.** I will only read and plan, not write files.", role = "assistant")
  })

  # /compact — no arguments
  mod$slash_command("compact", "Compact the context", function() {
    mod$append("Context compaction requested. (In real codeagent this triggers CompactionController.)", role = "assistant")
  })

  # /rewind — takes numeric argument via ContentSlashCommand@user_text
  mod$slash_command("rewind", "Rewind N exchanges", function(content) {
    raw  <- trimws(content@user_text)
    n    <- suppressWarnings(as.integer(raw))
    if (is.na(n) || n < 1L) {
      mod$append("Usage: `/rewind 2` — pass the number of exchanges to remove.", role = "assistant")
    } else {
      turns <- chat$get_turns()
      keep  <- max(0L, length(turns) - n * 2L)
      chat$set_turns(turns[seq_len(keep)])
      mod$append(sprintf("Rewound %d exchange(s). %d turns remain.", n, keep), role = "assistant")
    }
  })

  # /clear — no arguments
  mod$slash_command("clear", "Clear chat and reset history", function() {
    mod$clear(
      messages       = list(list(role = "assistant", content = "Chat cleared.")),
      client_history = "clear"
    )
  })
}

shinyApp(ui, server)
