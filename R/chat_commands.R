#' @title Local (slash) command dispatch -- pure decision layer
#' @description
#'   `.chat_command_result()` decides *what* a local `/command` should do given a
#'   handful of read-only facts, and returns a plain description
#'   (`list(action, feedback, ...)`). It performs **no** side effects: no chat
#'   mutation, no I/O, no Shiny calls. The Shiny handler
#'   (`.handle_chat_command`, server_chat.R) gathers the facts, calls this, then
#'   applies the effects (append message, show modal, truncate turns, compact).
#'   Keeping the decision pure makes every command's logic unit-testable without
#'   a running app -- see `tests/testthat/test-chat-commands.R`.
#' @name chat_commands
#' @keywords internal
NULL

# Decide the outcome of a local command. PURE.
#
# @param name Command name (without the leading '/').
# @param args Trailing argument string.
# @param n_tokens,model_limit Token budget facts (for /budget).
# @param n_turns Current number of chat turns (for /rewind).
# @param sessions A list of saved-session records (for /sessions).
# @return list(action, feedback = NULL, ...). Actions:
#   * "append"       -- just append `feedback` to the chat.
#   * "clear"        -- clear turns, then append `feedback`.
#   * "rewind"       -- truncate to `keep` turns, then append `feedback`.
#   * "modal_model"  -- open the model picker modal (feedback set by handler).
#   * "model_switch" -- switch to `args`, then append handler-built feedback.
#   * "compact"      -- run compaction (handler owns the async UI).
.chat_command_result <- function(name, args = "",
                                  n_tokens = 0L, model_limit = 200000L,
                                  n_turns = 0L, sessions = list()) {
  name <- name %||% ""
  args <- args %||% ""

  switch(name,
    model = if (!nzchar(trimws(args)))
              list(action = "modal_model")
            else
              list(action = "model_switch", args = trimws(args)),

    compact = list(action = "compact", args = trimws(args)),

    clear = list(action = "clear", feedback = "OK History cleared."),

    rewind = {
      n_back <- suppressWarnings(as.integer(trimws(args)))
      if (is.na(n_back) || n_back < 1L) n_back <- 1L
      keep <- max(0L, n_turns - 2L * n_back)
      list(action   = "rewind",
           keep     = keep,
           n_back   = n_back,
           feedback = sprintf("<<< Rewound %d exchange(s); %d turns kept.",
                              n_back, keep))
    },

    budget = {
      pct <- if (model_limit > 0L) round(n_tokens / model_limit * 100) else 0L
      list(action = "append",
           feedback = sprintf("**Token budget**: %s / %s tokens (%d%%)",
                              format(n_tokens, big.mark = ","),
                              format(model_limit, big.mark = ","), pct))
    },

    sessions = list(action = "append",
                    feedback = .format_sessions_feedback(sessions)),

    help = ,
    exit = ,
    quit = list(action = "append", feedback = .slash_help_text()),

    # Unknown local command -> help.
    list(action = "append", feedback = .unknown_command_text(name))
  )
}

# Format a saved-session list into a Markdown feedback string. PURE.
.format_sessions_feedback <- function(sessions) {
  if (!length(sessions)) return("No saved sessions.")
  lines <- vapply(sessions, function(s) {
    sprintf("- `%s`  %s",
            substr(s$session_id %||% "", 1L, 8L),
            s$title %||% s$timestamp %||% "")
  }, character(1))
  paste0("**Recent sessions**\n", paste(lines, collapse = "\n"))
}

# Built-in slash-command help. PURE.
.slash_help_text <- function() {
  paste0(
    "**Slash commands**\n",
    "- `/model [spec]` -- switch model (popup if no arg)\n",
    "- `/compact` -- compact the context now\n",
    "- `/clear` -- clear the conversation\n",
    "- `/rewind [N]` -- rewind the last N exchange(s)\n",
    "- `/budget` -- show token usage\n",
    "- `/sessions` -- list recent saved sessions\n",
    "- `/<skill> [args]` -- invoke a skill (sent to the model)"
  )
}

# Message for an unrecognised local command. PURE.
.unknown_command_text <- function(name) {
  paste0(
    "Unknown command: `/", name, "`.\n\n",
    "Built-in commands: `/model`, `/compact`, `/clear`, `/rewind [N]`, ",
    "`/budget`, `/sessions`, `/help`"
  )
}
