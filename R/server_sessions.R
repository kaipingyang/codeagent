#' @title Sessions Server Logic
#' @name server_sessions
#' @keywords internal
NULL

server_sessions <- function(input, output, session, chat, cwd,
                              state, stream_task, settings = list()) {

  output$session_list_ui <- shiny::renderUI({
    # Re-render whenever a session is saved (sessions_dirty, bumped after
    # save_session in server_chat) or the current session changes (New / Delete
    # / load), so the list stays fresh instead of a startup-only snapshot.
    state$sessions_dirty
    state$session_id
    sessions <- tryCatch(list_sessions(cwd, limit = 10L),
                         error = function(e) list())
    if (length(sessions) == 0L)
      return(htmltools::tags$p(
        style = "color:var(--bs-secondary-color, #6c757d); font-size:0.75rem; padding:4px 0;",
        "No saved sessions"))

    # Delegated click -> single observeEvent(input$ca_load_session) below (no
    # per-button observers, which only covered startup sessions). session_id is
    # a UUID, safe to embed in the onclick.
    buttons <- lapply(sessions, function(s) {
      sid   <- s$session_id
      label <- substr(s$summary %||% sid, 1L, 32L)
      htmltools::tags$button(
        type    = "button",
        class   = "ca-session-btn btn btn-outline-secondary btn-sm w-100 mb-1 text-start",
        onclick = sprintf(
          "Shiny.setInputValue('ca_load_session','%s',{priority:'event'});", sid),
        label
      )
    })
    htmltools::tagList(buttons)
  })

  # New session: clear in-memory state + assign a fresh session_id.
  # The current session file is kept in history (auto-save already wrote it).
  shiny::observeEvent(input$new_session, {
    if (!is.null(stream_task) && stream_task$status() == "running") return()
    tryCatch(chat$set_turns(list()), error = function(e) NULL)
    .reset_session_state(state)
    shinychat::chat_clear("chat", session)
    state$sessions_dirty <- (state$sessions_dirty %||% 0L) + 1L
  })

  # Delete session: remove the current session file and start fresh.
  shiny::observeEvent(input$delete_session_btn, {
    if (!is.null(stream_task) && stream_task$status() == "running") return()
    sid <- state$session_id
    if (!is.null(sid)) {
      tryCatch(delete_session(sid, directory = cwd), error = function(e) NULL)
    }
    tryCatch(chat$set_turns(list()), error = function(e) NULL)
    .reset_session_state(state)
    shinychat::chat_clear("chat", session)
    state$sessions_dirty <- (state$sessions_dirty %||% 0L) + 1L
    .ui_toast("Session deleted.", "message")
  })

  # Session load (delegated): one observer handles any session button click.
  shiny::observeEvent(input$ca_load_session, {
    if (!is.null(stream_task) && stream_task$status() == "running") return()
    sid <- input$ca_load_session
    if (is.null(sid) || !nzchar(sid)) return()
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
    # Refresh the CONTEXT token meter for the restored conversation (the stream
    # task only updates it on new turns, so a freshly restored session would
    # otherwise read 0 tokens).
    tryCatch({
      n_tokens    <- token_count_with_estimation(chat)
      model_limit <- settings$model_limit %||% 200000L
      session$sendCustomMessage("update_budget",
        .budget_payload(n_tokens, model_limit, settings$model %||% ""))
    }, error = function(e) NULL)
    shiny::showNotification(
      paste0("Session loaded: ", substr(sid, 1L, 8L), "..."),
      type = "message", duration = 3)
  }, ignoreInit = TRUE)
}

# ---------------------------------------------------------------------------
# Fresh-session state reset (shared by New + Delete)
# ---------------------------------------------------------------------------

# Reset the per-conversation slots of the shared `state` container to a fresh
# session: a new session_id, zeroed iteration, cleared output, and reset
# compaction / resource / budget controllers. Kept separate (and free of chat /
# session side effects) so the reset is unit-testable with a stub state and so
# New + Delete cannot drift apart. Callers still handle chat$set_turns() +
# chat_clear() (Shiny/chat side effects) around it.
.reset_session_state <- function(state) {
  state$session_id  <- tryCatch(.generate_uuid_v4(), error = function(e) "default")
  state$iteration   <- 0L
  state$main_output <- NULL
  tryCatch(state$compaction_ctrl$reset_failures(), error = function(e) NULL)
  tryCatch(state$resource_state$reset(),           error = function(e) NULL)
  tryCatch(state$budget_tracker$reset(),           error = function(e) NULL)
  invisible(state)
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

  # A content block is "empty" if it is a character value with no visible text.
  # Empty assistant turns (tool-only or interrupted responses that were saved
  # with no text) otherwise render as a bubble stuck showing the "..." typing
  # indicator on restore -- so we drop them. Non-character blocks (tool
  # request/result cards, thinking panels) are never treated as empty.
  .is_empty_block <- function(b) {
    is.character(b) && !nzchar(trimws(paste(b, collapse = "")))
  }

  for (item in items) {
    role    <- item$role %||% "assistant"
    content <- item$content
    if (!role %in% c("user", "assistant")) next

    # Scalar content (single text block)
    if (!is.list(content)) {
      disp <- if (identical(role, "user")) .strip_system_reminder(content) else content
      if (.is_empty_block(disp)) next   # no empty "..." bubble on restore
      tryCatch(
        shinychat::chat_append_message("chat",
          list(role = role, content = disp),
          chunk = FALSE, session = session),
        error = function(e) NULL)
      next
    }

    # List content (multiple blocks: text + tool cards mixed). Strip reminders
    # from user text, drop empty blocks, then group with the chunk protocol.
    blocks <- lapply(content, function(b) {
      if (identical(role, "user") && is.character(b)) .strip_system_reminder(b) else b
    })
    blocks <- Filter(function(b) !.is_empty_block(b), blocks)
    n <- length(blocks)
    if (n == 0L) next   # whole turn was empty -> skip (no stuck "..." bubble)

    # chunk="start"/TRUE/"end" groups the blocks into one bubble; recomputed on
    # the FILTERED list so a single remaining block sends chunk=FALSE (a
    # complete message) rather than opening a stream that is never closed.
    for (j in seq_len(n)) {
      chunk_arg <- if (n == 1L) FALSE
                   else if (j == 1L) "start"
                   else if (j == n) "end"
                   else TRUE
      tryCatch(
        shinychat::chat_append_message("chat",
          list(role = role, content = blocks[[j]]),
          chunk = chunk_arg, session = session),
        error = function(e) NULL)
    }
  }
  invisible(NULL)
}
