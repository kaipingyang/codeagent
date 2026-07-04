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
  local_defs <- lapply(.LOCAL_COMMANDS, function(nm) {
    list(name = nm, description = unname(local_desc[nm]) %||% nm, echo = FALSE)
  })

  skill_defs <- tryCatch({
    metas <- list_skills_meta(cwd)
    lapply(metas, function(m) {
      list(name = m$name, description = m$description %||% m$name, echo = FALSE)
    })
  }, error = function(e) list())

  # De-duplicate by name (a command may also be a skill, e.g. /compact).
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
#' @return Invisibly NULL.
#' @keywords internal
server_slash <- function(input, session, cwd = getwd(), id = "chat") {
  # Register commands once the client has connected (after the first flush).
  tryCatch(
    session$onFlushed(function() .send_slash_commands(session, cwd, id),
                      once = TRUE),
    error = function(e) .send_slash_commands(session, cwd, id))

  # Selection -> reconstruct "/command args" and submit through the normal input
  # so server_chat's single routing path handles it.
  shiny::observeEvent(input[[paste0(id, "_slash_command")]], {
    data <- input[[paste0(id, "_slash_command")]]
    cmd  <- if (is.list(data)) data$command else NULL
    if (is.null(cmd) || !nzchar(cmd)) return()
    ut   <- if (is.list(data)) (data$userText %||% "") else ""
    val  <- paste0("/", cmd, if (nzchar(ut)) paste0(" ", ut) else "")
    tryCatch(
      shinychat::update_chat_user_input(id, value = val, submit = TRUE,
                                        session = session),
      error = function(e) NULL)
  })
  invisible(NULL)
}
