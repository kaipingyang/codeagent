#' @title Sessions Server Logic
#' @name server_sessions
#' @keywords internal
NULL

server_sessions <- function(input, output, session, chat, cwd,
                              state, stream_task, settings = list()) {

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
          # Replay via contents_shinychat -- native tool card rendering.
          .replay_turns_to_ui(chat, session)
          # Refresh the CONTEXT token meter for the restored conversation
          # (the stream task only updates it on new turns, so a freshly
          # restored session would otherwise read 0 tokens).
          tryCatch({
            n_tokens    <- token_count_with_estimation(chat)
            model_limit <- settings$model_limit %||% 200000L
            session$sendCustomMessage("update_budget",
              .budget_payload(n_tokens, model_limit, settings$model %||% ""))
          }, error = function(e) NULL)
          shiny::showNotification(
            paste0("Session loaded: ", substr(sid, 1L, 8L), "..."),
            type = "message", duration = 3)
        }, ignoreNULL = TRUE, ignoreInit = TRUE)
      })
    })
  })
}

# ---------------------------------------------------------------------------
# Turn-based UI replay via contents_shinychat (native tool card rendering)
# ---------------------------------------------------------------------------

# Replay an ellmer Chat into the shinychat UI using shinychat's own
# contents_shinychat() S7 generic. This handles all content types natively:
#   ContentText        -> markdown text bubble
#   ContentToolRequest -> <shiny-tool-request> native card
#   ContentToolResult  -> <shiny-tool-result> native card
#   ContentThinking    -> collapsible thinking panel
#
# For assistant turns with mixed content (text + tool cards), we send each
# block using the chunk="start" / chunk=TRUE / chunk="end" protocol so
# shinychat groups them into a single message bubble.
.replay_turns_to_ui <- function(chat, session) {
  items <- tryCatch(
    shinychat::contents_shinychat(chat),
    error = function(e) list())
  if (!length(items)) return(invisible(NULL))

  for (item in items) {
    role    <- item$role %||% "assistant"
    content <- item$content
    if (!role %in% c("user", "assistant")) next

    # Scalar content (single text block)
    if (!is.list(content)) {
      disp <- if (identical(role, "user")) .strip_system_reminder(content) else content
      tryCatch(
        shinychat::chat_append_message("chat",
          list(role = role, content = disp),
          chunk = FALSE, session = session),
        error = function(e) NULL)
      next
    }

    # List content (multiple blocks: text + tool cards mixed).
    # Use chunk="start" / chunk=TRUE / chunk="end" so shinychat groups them.
    n <- length(content)
    for (j in seq_len(n)) {
      block     <- content[[j]]
      if (identical(role, "user") && is.character(block))
        block <- .strip_system_reminder(block)
      chunk_arg <- if (j == 1L && n > 1L) "start"
                   else if (j == n && n > 1L) "end"
                   else if (n == 1L) FALSE
                   else TRUE
      tryCatch(
        shinychat::chat_append_message("chat",
          list(role = role, content = block),
          chunk = chunk_arg, session = session),
        error = function(e) NULL)
    }
  }
  invisible(NULL)
}
