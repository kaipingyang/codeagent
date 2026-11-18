#' @title shinychat conversation history for host apps
#' @description `codeagent_server(history = shinychat::history_options(...))`:
#'   shinychat's history drawer (list, switch, new, rename, delete) on top of
#'   codeagent's engine.
#'
#' shinychat records a conversation from the turns of the Chat it is given,
#' after each `chat_append()` stream. codeagent therefore gives it a separate
#' *presentation* Chat that holds what the user saw -- user messages without
#' the injected `<system-reminder>`, tool calls with gated arguments, model
#' text after the Data Shield output gate -- and only ever grows: compaction
#' changes the model's context, never this record. The model's own context is
#' restored from codeagent's session log ([save_session()]) through the
#' session id stored with each record.
#' @name history_shinychat
#' @keywords internal
NULL

.enable_shinychat_history <- function(input, session, chat, core, options,
                                      greeting = NULL, on_restore = NULL) {
  if (!inherits(options, "chat_history_config"))
    stop("`history` must be NULL, \"codeagent\" or shinychat::history_options().",
         call. = FALSE)
  settings <- core$settings
  state    <- core$state
  cwd      <- settings$cwd %||% getwd()

  pres <- chat$clone(deep = FALSE)
  .copy_chat_attrs(chat, pres)
  pres$set_turns(list())
  # On the Chat (a reference, like the Data Shield attribute): the streaming
  # task reads it from there.
  attr(chat, "codeagent_presentation_chat") <- pres

  send_budget <- function() tryCatch({
    n <- token_count_with_estimation(chat, allow_network = FALSE)
    session$sendCustomMessage("update_budget",
      .budget_payload(n, settings$model_limit %||% 200000L, settings$model %||% ""))
  }, error = function(e) NULL)
  show_greeting <- function() if (!is.null(greeting)) tryCatch(
    shinychat::chat_set_greeting("chat", .as_host_greeting(greeting), session = session),
    error = function(e) NULL)

  cancel <- shinychat::chat_enable_history(
    "chat", pres, options = options, session = session,
    # Saved with every record: the codeagent session that holds the model's
    # lossless context for this conversation.
    on_save = function(values) {
      values$codeagent_session_id <- shiny::isolate(state$session_id)
      values
    },
    # A conversation was opened: the model continues from its saved context
    # (the last compaction boundary on), the canvas comes back with it.
    on_restore = function(values) {
      sid <- values$codeagent_session_id
      ok <- !is.null(sid) && !is.null(.validate_uuid(sid)) && !is.null(tryCatch(
        restore_session_into_chat(chat, session_id = sid, cwd = cwd),
        error = function(e) NULL))
      if (!ok) {
        # no log for it (other app, deleted): continue from what was shown
        chat$set_turns(pres$get_turns())
        sid <- .generate_uuid_v4()
      }
      shiny::isolate(state$session_id <- sid)
      tryCatch(.genui_restore_ui(settings, chat, sid, cwd), error = function(e) NULL)
      send_budget()
      if (is.function(on_restore)) tryCatch(on_restore(chat), error = function(e)
        .ui_toast(paste0("Restoring the host view failed: ", conditionMessage(e)), "warning"))
    })

  # New chat: shinychat empties the presentation Chat; empty the model's too.
  shiny::observeEvent(input$chat_history_new, {
    chat$set_turns(list())
    tryCatch(.genui_reset(settings), error = function(e) NULL)
    .reset_session_state(state)
    show_greeting()
    send_budget()
  }, ignoreInit = TRUE, priority = -10)

  # Editing a message forks the conversation, and the sibling arrows switch
  # branches: shinychat sets the presentation Chat to that branch; the model
  # continues from it too (and the session log records the change).
  follow_branch <- function() {
    chat$set_turns(pres$get_turns())
    .session_sync_context(chat, cwd, shiny::isolate(state$session_id), "rewind")
    send_budget()
  }
  shiny::observeEvent(input$chat_message_edit, follow_branch(),
                      ignoreInit = TRUE, priority = -10)
  shiny::observeEvent(input$chat_message_navigate, follow_branch(),
                      ignoreInit = TRUE, priority = -10)

  invisible(cancel)
}

.as_host_greeting <- function(greeting) {
  if (inherits(greeting, "shinychat_greeting")) greeting
  else shinychat::chat_greeting(greeting, persistent = TRUE)
}

# Append the turns of the round that just finished to the presentation Chat,
# as the user saw them. Must run before the last chat_append() of the round
# resolves: shinychat saves the record when it does.
.append_presentation <- function(settings, chat, round_start, shown_text = NULL) {
  pres <- tryCatch(attr(chat, "codeagent_presentation_chat"), error = function(e) NULL)
  if (is.null(pres)) return(invisible(FALSE))
  turns <- tryCatch(chat$get_turns(), error = function(e) list())
  new <- if (length(turns) > round_start) turns[(round_start + 1L):length(turns)] else list()
  new <- Filter(function(t) !.turn_is_empty(t), new)
  if (!length(new)) return(invisible(FALSE))
  shown <- .presentation_turns(new, settings, chat, shown_text)
  tryCatch(pres$set_turns(c(pres$get_turns(), shown)), error = function(e) NULL)
  invisible(TRUE)
}

# Turns as the user saw them. User text without <system-reminder>; tool
# calls with arguments that pass the output gate (else none); model text
# through the output gate, the last reply replaced by `shown_text` (the
# finalized, gated text) when given; thinking only when nothing is gated.
.presentation_turns <- function(turns, settings, chat, shown_text = NULL) {
  gated <- !is.null(.input_gate_shield(settings, chat))
  roles <- vapply(turns, function(t) tryCatch(t@role, error = function(e) ""), "")
  last_assistant <- utils::tail(which(roles == "assistant"), 1L)
  out <- list()
  for (i in seq_along(turns)) {
    contents <- tryCatch(turns[[i]]@contents, error = function(e) list())
    keep <- list()
    replaced <- FALSE
    for (x in contents) {
      if (S7::S7_inherits(x, ellmer::ContentToolRequest)) {
        keep[[length(keep) + 1L]] <- .gated_tool_request(x, settings, chat)
      } else if (S7::S7_inherits(x, ellmer::ContentToolResult)) {
        req <- tryCatch(x@request, error = function(e) NULL)
        if (!is.null(req)) x@request <- .gated_tool_request(req, settings, chat)
        keep[[length(keep) + 1L]] <- x
      } else if (S7::S7_inherits(x, ellmer::ContentThinking)) {
        if (!gated) keep[[length(keep) + 1L]] <- x
      } else if (S7::S7_inherits(x, ellmer::ContentText)) {
        txt <- tryCatch(x@text, error = function(e) "")
        if (identical(roles[[i]], "user")) {
          txt <- .strip_system_reminder(txt)
        } else if (length(last_assistant) && identical(i, last_assistant) && !is.null(shown_text)) {
          if (replaced) next
          txt <- shown_text; replaced <- TRUE
        } else if (gated) {
          txt <- .output_gate_guarded(txt, settings, chat)$text %||% ""
        }
        if (nzchar(trimws(txt))) keep[[length(keep) + 1L]] <- ellmer::ContentText(txt)
      } else {
        keep[[length(keep) + 1L]] <- x
      }
    }
    if (length(last_assistant) && identical(i, last_assistant) && !replaced &&
        !is.null(shown_text) && nzchar(trimws(shown_text)))
      keep[[length(keep) + 1L]] <- ellmer::ContentText(shown_text)
    if (length(keep)) out[[length(out) + 1L]] <- ellmer::Turn(roles[[i]], keep)
  }
  out
}
