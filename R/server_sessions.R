#' @title Sessions Server Logic
#' @name server_sessions
#' @keywords internal
NULL

server_sessions <- function(input, output, session, chat, cwd,
                              state, stream_task) {

  output$session_list_ui <- shiny::renderUI({
    sessions <- tryCatch(list_sessions(cwd, limit = 10L),
                         error = function(e) list())
    if (length(sessions) == 0L)
      return(htmltools::tags$p(
        style = "color:var(--bs-secondary-color, #6c757d); font-size:0.75rem; padding:4px 0;",
        "No saved sessions"))

    buttons <- lapply(sessions, function(s) {
      label <- substr(s$summary %||% s$session_id, 1L, 32L)
      shiny::actionButton(
        inputId = paste0("load_sess_", s$session_id),
        label   = label,
        class   = "ca-session-btn w-100 mb-1 btn-sm"
      )
    })
    htmltools::tagList(buttons)
  })

  # New session: clear in-memory state + assign a fresh session_id.
  # The current session file is kept in history (auto-save already wrote it).
  shiny::observeEvent(input$new_session, {
    if (!is.null(stream_task) && stream_task$status() == "running") return()
    tryCatch(chat$set_turns(list()), error = function(e) NULL)
    state$session_id  <- tryCatch(.generate_uuid_v4(), error = function(e) "default")
    state$iteration   <- 0L
    state$main_output <- NULL
    state$compaction_ctrl$reset_failures()
    state$resource_state$reset()
    state$budget_tracker$reset()
    shinychat::chat_clear("chat", session)
  })

  # Delete session: remove the current session file and start fresh.
  shiny::observeEvent(input$delete_session_btn, {
    if (!is.null(stream_task) && stream_task$status() == "running") return()
    sid <- state$session_id
    if (!is.null(sid)) {
      tryCatch(delete_session(sid, directory = cwd), error = function(e) NULL)
    }
    tryCatch(chat$set_turns(list()), error = function(e) NULL)
    state$session_id  <- tryCatch(.generate_uuid_v4(), error = function(e) "default")
    state$iteration   <- 0L
    state$main_output <- NULL
    state$compaction_ctrl$reset_failures()
    state$resource_state$reset()
    state$budget_tracker$reset()
    shinychat::chat_clear("chat", session)
    .ui_toast("Session deleted.", "message")
  })

  # Session load buttons
  shiny::observe({
    sessions <- tryCatch(list_sessions(cwd, limit = 10L),
                         error = function(e) list())
    lapply(sessions, function(s) {
      btn_id <- paste0("load_sess_", s$session_id)
      local({
        sid <- s$session_id
        shiny::observeEvent(input[[btn_id]], {
          if (!is.null(stream_task) && stream_task$status() == "running") return()
          # Restore lossless chat state (tool calls preserved).
          ok <- tryCatch({
            restore_session_into_chat(chat, session_id = sid, cwd = cwd)
            TRUE
          }, error = function(e) FALSE)
          if (!isTRUE(ok)) {
            shiny::showNotification("Session could not be loaded.",
                                    type = "warning", duration = 3)
            return()
          }
          state$session_id <- sid
          shinychat::chat_clear("chat", session)
          # Replay from restored turns (includes tool calls) rather than the
          # text-only get_session_messages path which dropped tool content.
          .replay_turns_to_ui(chat$get_turns(), session, state)
          shiny::showNotification(
            paste0("Session loaded: ", substr(sid, 1L, 8L), "..."),
            type = "message", duration = 3)
        }, ignoreNULL = TRUE, ignoreInit = TRUE)
      })
    })
  })
}

# ---------------------------------------------------------------------------
# Turn-based UI replay  (preserves tool call cards)
# ---------------------------------------------------------------------------

# Replay a list of ellmer Turns back into the shinychat UI so that both
# text messages and tool call cards are shown -- unlike get_session_messages
# which only extracted plain text and silently dropped all tool content.
#
# For each Turn:
#   user/assistant text -> chat_append_message (markdown rendered)
#   ContentToolResult   -> .adapt_tool_result + push to Output panel
#                          + chat_append_message with tool card summary
.replay_turns_to_ui <- function(turns, session, state) {
  if (!length(turns)) return(invisible(NULL))
  for (turn in turns) {
    role <- tryCatch(turn@role, error = function(e) "assistant")
    if (!role %in% c("user", "assistant")) next
    contents <- tryCatch(turn@contents, error = function(e) list())
    # Collect text parts and tool results separately.
    text_parts   <- character(0)
    tool_results <- list()
    for (ct in contents) {
      cls <- class(ct)[1L]
      if (grepl("ContentText|ContentThinking", cls, fixed = FALSE)) {
        txt <- tryCatch(ct@text %||% ct@thinking %||% "", error = function(e) "")
        if (nzchar(txt)) text_parts <- c(text_parts, txt)
      } else if (grepl("ContentToolResult", cls, fixed = FALSE)) {
        tool_results <- c(tool_results, list(ct))
      }
    }
    # Append text part.
    combined_text <- paste(text_parts, collapse = "\n\n")
    if (nzchar(combined_text)) {
      md_html <- tryCatch(
        htmltools::HTML(commonmark::markdown_html(combined_text)),
        error = function(e) htmltools::HTML(combined_text))
      tryCatch(
        shinychat::chat_append_message("chat",
          list(role = role, content = md_html),
          chunk = FALSE, session = session),
        error = function(e) NULL)
    }
    # Append tool result cards.
    for (res in tool_results) {
      adapted <- tryCatch(.adapt_tool_result(res), error = function(e) res)
      # Push to Output panel (same as the live path).
      display  <- tryCatch(adapted@extra$display, error = function(e) NULL)
      if (!is.null(display)) {
        title   <- tryCatch(
          gsub("<[^>]+>", "", as.character(display$title %||%
            display$toolcard$title %||% "Tool")),
          error = function(e) "Tool")
        content <- tryCatch(render_tool_output(display), error = function(e) NULL)
        if (!is.null(content))
          state$main_output <- list(title = title, content = content)
      }
      # Append a summary card in the chat bubble.
      tool_name <- tryCatch(res@request@name %||% "tool", error = function(e) "tool")
      val       <- tryCatch(as.character(adapted@value), error = function(e) "")
      summary   <- if (nzchar(val)) substr(val, 1L, 200L) else "(done)"
      card_html <- htmltools::HTML(paste0(
        "<div class='ca-tool-replay'>",
        "<span class='ca-tool-name'><code>", htmltools::htmlEscape(tool_name), "</code></span> ",
        "<span class='ca-tool-summary'>", htmltools::htmlEscape(summary), "</span>",
        "</div>"))
      tryCatch(
        shinychat::chat_append_message("chat",
          list(role = "assistant", content = card_html),
          chunk = FALSE, session = session),
        error = function(e) NULL)
    }
  }
  invisible(NULL)
}
