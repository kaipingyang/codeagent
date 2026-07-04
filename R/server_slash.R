#' @title Official shinychat slash-command typeahead (standalone driver)
#' @description Drives shinychat's **official** slash-command typeahead palette
#'   (dev feature #239: the native `/`-triggered command menu) WITHOUT using
#'   `shinychat::chat_server()`.
#'
#'   codeagent owns its own streaming (`server_chat()` + `stream_task`), so it
#'   cannot adopt `chat_server()` (whose input observer would double-stream every
#'   message alongside codeagent's harness -- see
#'   `lessons/2026-07-03-shiny-async-interaction.md`). shinychat has no public
#'   standalone `register_slash_command()` yet (upstream TODO), so we speak its
#'   client protocol directly:
#'
#'   * **Register**: send `{type: "update_slash_commands", commands: [...]}` via
#'     the `shinyChatMessage` custom message (same envelope shinychat's
#'     `send_chat_action()` uses). Each command is `{name, description, echo}`.
#'   * **Select**: the client sends `input$<id>_slash_command = {command, userText}`.
#'     We reconstruct `/command args` and submit it through the normal input via
#'     `update_chat_user_input(submit = TRUE)`, so all routing stays in the one
#'     place (`server_chat` -> `.preprocess_input`): local commands are handled
#'     client-of-LLM, skills inject their prompt, etc.
#'
#'   Graceful degradation: on a shinychat build without the typeahead, the
#'   registration message is simply ignored and the footer `pickerInput` remains
#'   as the fallback slash UI. REPL is unaffected (uses `.preprocess_input`).
#' @name server_slash
#' @keywords internal
NULL

# Build the slash-command definitions for the client typeahead: local commands
# (handled without the LLM) + discovered skills. echo = FALSE for all, because
# codeagent re-submits the reconstructed input through the normal path, which
# renders the user message itself (avoids a double user bubble).
.slash_command_defs <- function(cwd = getwd()) {
  local_desc <- c(
    model    = "Switch the model", compact = "Compact the context now",
    clear    = "Clear the conversation", rewind = "Rewind the last turn(s)",
    help     = "Show help", sessions = "List saved sessions",
    budget   = "Show token budget"
  )
  # Local commands: echo = FALSE. They do NOT go to the LLM, so we must not let
  # shinychat enter its "awaitResponse" (loading spinner waiting for AI) state.
  # We render the user-echo bubble + result ourselves in the dispatcher so the
  # invocation is still visible in the chat log (matching assistant-ui /
  # Claude Code convention) without a hanging loading state.
  local_defs <- lapply(.LOCAL_COMMANDS, function(nm) {
    list(name = nm, description = unname(local_desc[nm]) %||% nm, echo = FALSE)
  })

  # Skill commands: echo = TRUE (shinychat's default for handler-backed
  # commands). shinychat renders the "/skill args" user bubble and enters the
  # awaitResponse state, which is correct because skills DO invoke the LLM.
  skill_defs <- tryCatch({
    metas <- list_skills_meta(cwd)
    lapply(metas, function(m) {
      list(name = m$name, description = m$description %||% m$name, echo = TRUE)
    })
  }, error = function(e) list())

  # De-duplicate by name (a command may also be a skill, e.g. /compact).
  # Local wins on conflict (its echo=FALSE + manual handling is intentional).
  all_defs <- c(local_defs, skill_defs)
  seen <- character(0)
  out  <- list()
  for (d in all_defs) {
    if (is.null(d$name) || d$name %in% seen) next
    seen <- c(seen, d$name)
    out  <- c(out, list(d))
  }
  out
}

# Send the command definitions to the client typeahead (shinychat protocol).
.send_slash_commands <- function(session, cwd = getwd(), id = "chat") {
  defs <- tryCatch(.slash_command_defs(cwd), error = function(e) list())
  if (!length(defs)) return(invisible(FALSE))
  resolved <- tryCatch(session$ns(id), error = function(e) id)
  if (is.null(resolved) || !nzchar(resolved)) resolved <- id
  tryCatch(
    session$sendCustomMessage("shinyChatMessage", list(
      id     = resolved,
      action = list(type = "update_slash_commands", commands = defs)
    )),
    error = function(e) NULL)
  invisible(TRUE)
}

#' Wire the official slash-command typeahead for a chat input
#'
#' @param input,session Standard Shiny server args.
#' @param cwd Character. Working directory (for skill discovery).
#' @param id Character. The `chat_ui()` id (default `"chat"`).
#' @param stream_task The `ExtendedTask` returned by [server_chat()], used to
#'   run skill/normal slash commands through the harness (compaction, skill
#'   injection, streaming). Required for skill commands to reach the LLM.
#' @param chat,settings,state,exec_command Harness handles for executing local
#'   commands directly. `exec_command` is a function
#'   `function(parsed)` that runs a local command (wraps
#'   `.handle_chat_command`); when supplied it is used instead of the
#'   chat/settings/state trio.
#' @return Invisibly NULL.
#' @details
#'   Slash commands are dispatched **directly inside this handler** — we do NOT
#'   re-submit `/command` through `update_chat_user_input()`. Re-submitting is
#'   broken: shinychat re-recognises the re-submitted `/command` as a slash
#'   command and fires `input$<id>_slash_command` again with the *same* value,
#'   which Shiny's `observeEvent` de-dupes into a no-op — so the command never
#'   reaches `input$<id>_user_input` / `.preprocess_input` and silently dies.
#'   Instead we mirror `server_chat`'s routing here: local commands run via
#'   `.handle_chat_command()`, skills/normal go through the shared `stream_task`
#'   (which injects the skill prompt internally).
#' @keywords internal
server_slash <- function(input, session, cwd = getwd(), id = "chat",
                         stream_task = NULL,
                         chat = NULL, settings = NULL, state = NULL) {
  # Register commands once the client has connected (after the first flush).
  tryCatch(
    session$onFlushed(function() .send_slash_commands(session, cwd, id),
                      once = TRUE),
    error = function(e) .send_slash_commands(session, cwd, id))

  # Selection -> dispatch DIRECTLY (never re-submit; see @details).
  shiny::observeEvent(input[[paste0(id, "_slash_command")]], {
    parsed <- .slash_parse_selection(input[[paste0(id, "_slash_command")]])
    if (is.null(parsed)) return()

    if (identical(parsed$type, "command")) {
      # Local command: does NOT touch the LLM (echo=FALSE, so shinychat renders
      # no bubble and no loading state). To keep the invocation visible in the
      # chat log -- matching assistant-ui / Claude Code convention where the
      # command AND its result are shown -- we manually echo the "/command args"
      # as a user bubble here; .handle_chat_command() then appends the result
      # (or opens a dialog, e.g. /model).
      echo_val <- paste0("/", parsed$name,
                         if (nzchar(parsed$args)) paste0(" ", parsed$args) else "")
      tryCatch(
        shinychat::chat_append(id, echo_val, role = "user", session = session),
        error = function(e) NULL)
      if (!is.null(chat))
        tryCatch(.handle_chat_command(parsed, chat, settings, state, session, cwd),
                 error = function(e) NULL)
      return()
    }

    # Skill command: run through the shared stream_task, which injects the
    # skill prompt (.preprocess_input -> load_skill_prompt) before streaming.
    if (!is.null(stream_task)) {
      if (isTRUE(tryCatch(stream_task$status() == "running", error = function(e) FALSE)))
        return()
      val <- paste0("/", parsed$name,
                    if (nzchar(parsed$args)) paste0(" ", parsed$args) else "")
      tryCatch(stream_task$invoke(val), error = function(e) NULL)
    }
  })
  invisible(NULL)
}

# Parse a client `{command, userText}` selection into a routing decision.
# Pure + testable. Returns NULL for empty/invalid input; otherwise a list
# `list(type, name, args)` where `type` is "command" (local, run directly) or
# "skill" (needs the LLM, go through stream_task).
.slash_parse_selection <- function(data) {
  cmd <- if (is.list(data)) data$command else NULL
  if (is.null(cmd) || !is.character(cmd) || length(cmd) != 1L || !nzchar(cmd))
    return(NULL)
  ut <- if (is.list(data)) (data$userText %||% "") else ""
  if (!is.character(ut) || length(ut) != 1L) ut <- ""
  list(type = if (cmd %in% .LOCAL_COMMANDS) "command" else "skill",
       name = cmd, args = ut)
}
