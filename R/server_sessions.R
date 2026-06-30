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

  # New session
  shiny::observeEvent(input$new_session, {
    if (!is.null(stream_task) && stream_task$status() == "running") return()
    tryCatch(chat$set_turns(list()), error = function(e) NULL)
    state$session_id  <- NULL
    state$iteration   <- 0L
    state$main_output <- NULL
    state$compaction_ctrl$reset_failures()
    state$resource_state$reset()
    state$budget_tracker$reset()
    shinychat::chat_clear("chat", session)
  })

  # Save session
  shiny::observeEvent(input$save_session_btn, {
    sid <- state$session_id
    if (is.null(sid)) sid <- .generate_uuid_v4()
    tryCatch({
      save_session(chat, cwd, sid)
      state$session_id <- sid
      shiny::showNotification(
        paste0("Session saved: ", substr(sid, 1L, 8L), "…"),
        type = "message", duration = 3)
    }, error = function(e) {
      shiny::showNotification(
        paste0("Save failed: ", conditionMessage(e)),
        type = "error", duration = 5)
    })
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
          msgs <- tryCatch(get_session_messages(sid, cwd), error = function(e) list())
          if (length(msgs) == 0L) {
            shiny::showNotification("Session empty or could not be loaded.",
                                    type = "warning", duration = 3)
            return()
          }
          # Lossless history restore (tool calls preserved); UI bubbles still
          # use the text msgs below. Falls back to text turns for legacy files.
          tryCatch(restore_session_into_chat(chat, session_id = sid, cwd = cwd),
                   error = function(e) NULL)
          state$session_id <- sid
          shinychat::chat_clear("chat", session)
          lapply(msgs, function(m) {
            shinychat::chat_append_message(
              "chat",
              list(role = m$type, content = m$text),
              chunk   = FALSE,
              session = session)
          })
          shiny::showNotification(
            paste0("Session loaded: ", substr(sid, 1L, 8L), "…"),
            type = "message", duration = 3)
        }, ignoreNULL = TRUE, ignoreInit = TRUE)
      })
    })
  })
}
