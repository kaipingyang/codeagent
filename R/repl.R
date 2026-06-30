#' @title Interactive CLI REPL (harness, no Shiny)
#' @description A terminal read-eval-print loop for the agent. Reuses one
#'   `CodagentClient` so history accumulates in the Chat object across turns.
#'   Mirrors the Shiny `agent_loop()` turn pipeline so long sessions stay
#'   healthy: per-turn compaction, `<system-reminder>` injection, skill
#'   preprocessing, and auto-save -- the same harness objects the app uses.
#'
#'   Slash commands: `/model`, `/compact`, `/clear`, `/sessions`, `/budget`,
#'   `/help`, `/exit`. `/<skill>` invokes a skill via `load_skill_prompt()`.
#'   The line parser `.repl_dispatch()` is a pure function (testable); the loop
#'   `codeagent_repl()` handles IO + the turn pipeline.
#' @name repl
#' @keywords internal
NULL

# Built-in REPL meta-commands (everything else starting with "/" is a skill).
.REPL_META_CMDS <- c("exit", "quit", "help", "clear", "compact",
                     "model", "sessions", "budget")

# Parse one REPL line into an action descriptor (pure, testable).
# Returns list(action, ...). Actions:
#   exit/help/clear/compact/sessions/budget -> meta commands
#   model    -> switch model (arg = spec)
#   noop     -> empty line
#   skill    -> /name that is NOT a meta command -> load_skill_prompt (text=line)
#   prompt   -> plain text sent to the model (text = line)
.repl_dispatch <- function(line) {
  line <- trimws(line %||% "")
  if (!nzchar(line)) return(list(action = "noop"))
  if (!startsWith(line, "/")) return(list(action = "prompt", text = line))

  parts <- strsplit(sub("^/", "", line), "\\s+")[[1L]]
  cmd   <- tolower(parts[[1L]] %||% "")
  arg   <- if (length(parts) > 1L) paste(parts[-1L], collapse = " ") else ""

  if (!(cmd %in% .REPL_META_CMDS)) {
    # Not a built-in: treat as a skill invocation, pass the whole line through
    # the normal slash/skill preprocessor.
    return(list(action = "skill", text = line))
  }

  switch(cmd,
    exit     = ,
    quit     = list(action = "exit"),
    help     = list(action = "help"),
    clear    = list(action = "clear"),
    compact  = list(action = "compact"),
    sessions = list(action = "sessions"),
    budget   = list(action = "budget"),
    model    = list(action = "model", arg = arg)
  )
}

.repl_help <- paste(
  "Commands:",
  "  /model <spec>   switch model (e.g. anthropic/claude-haiku-4-5)",
  "  /compact        force context compaction",
  "  /clear          clear conversation history",
  "  /sessions       list recent saved sessions",
  "  /budget         show token usage vs limit",
  "  /<skill> [args] invoke a skill (e.g. /plan)",
  "  /help           show this help",
  "  /exit, /quit    leave the REPL",
  sep = "\n"
)

# Print a one-line token-budget status (only when usage is notable).
.repl_budget_line <- function(chat, settings) {
  n     <- tryCatch(estimate_tokens(chat), error = function(e) 0L)
  limit <- settings$model_limit %||% 200000L
  pct   <- if (limit > 0L) round(n / limit * 100) else 0L
  if (pct >= 50L)
    cat(sprintf("  [%s tokens / %d%%]\n", format(n, big.mark = ","), pct))
  invisible(NULL)
}

#' Run the interactive REPL
#'
#' @param client A `CodagentClient`.
#' @param stream Logical. Stream responses token-by-token.
#' @param prompt_str Character. The input prompt shown each turn.
#' @param con Connection to read lines from (default stdin; override in tests).
#' @param session_id Character or NULL. Session id for auto-save (generated if
#'   NULL).
#' @return Invisibly the session id. Loops until `/exit` or EOF.
#' @export
codeagent_repl <- function(client, stream = TRUE, prompt_str = "\u203a ",
                           con = NULL, session_id = NULL) {
  if (!inherits(client, "CodagentClient"))
    stop("codeagent_repl() expects a CodagentClient.", call. = FALSE)

  settings <- client$settings
  cwd      <- settings$cwd %||% getwd()

  # Resolve the input connection. Under Rscript, stdin() is an empty/non-blocking
  # connection that returns EOF immediately; file("stdin") opens fd 0 (the real
  # terminal) and blocks for interactive input. Tests pass an explicit con.
  owns_con <- FALSE
  if (is.null(con)) {
    con <- file("stdin")
    open(con, "r")
    owns_con <- TRUE
    on.exit(tryCatch(close(con), error = function(e) NULL), add = TRUE)
  }

  # Per-session harness state -- same objects the Shiny app/agent_loop use, so
  # the REPL benefits from compaction, budget tracking, and hooks.
  compaction_ctrl <- CompactionController$new()
  resource_state  <- ContentReplacementState$new()
  if (is.null(session_id))
    session_id <- tryCatch(.generate_uuid_v4(), error = function(e) "repl")
  iteration <- 1L

  cat("\n")
  ver <- tryCatch(as.character(utils::packageVersion("codeagent")),
                  error = function(e) "0.1.0")
  bar <- paste(rep("-", 40L), collapse = "")
  cat(bar, "\n")
  cat(sprintf("  codeagent %s\n", ver))
  cat(sprintf("  model: %s\n", settings$model %||% "(auto)"))
  cat(sprintf("  mode:  %s\n", settings$permission_mode %||% "default"))
  cat("  /help for commands, /exit to quit\n")
  cat(bar, "\n\n")

  repeat {
    cat(prompt_str)
    line <- tryCatch(readLines(con, n = 1L), error = function(e) character(0))
    if (length(line) == 0L) break  # EOF (Ctrl-D)

    act <- .repl_dispatch(line)

    # --- meta commands (do not reach the model) ---
    handled <- switch(act$action,
      noop = TRUE,
      exit = { cat("Bye.\n"); return(invisible(session_id)) },
      help = { cat(.repl_help, "\n"); TRUE },
      clear = {
        tryCatch(client$chat$set_turns(list()), error = function(e) NULL)
        cat("[history cleared]\n"); TRUE
      },
      compact = {
        tryCatch(full_compact(client$chat), error = function(e)
          cat("[compact failed: ", conditionMessage(e), "]\n", sep = ""))
        cat("[context compacted]\n"); TRUE
      },
      sessions = {
        sl <- tryCatch(list_sessions(cwd, limit = 10L), error = function(e) list())
        if (length(sl) == 0L) cat("  (no saved sessions)\n")
        else for (s in sl)
          cat(sprintf("  %s  %s\n", substr(s$session_id, 1L, 8L),
                      s$title %||% s$timestamp %||% ""))
        TRUE
      },
      budget = { .repl_budget_line(client$chat, settings); TRUE },
      model = {
        if (!nzchar(act$arg)) { cat("Usage: /model <spec>\n") }
        else {
          client <- tryCatch(switch_model(client, act$arg), error = function(e) {
            cat("[model switch failed: ", conditionMessage(e), "]\n", sep = ""); client
          })
          cat("[model: ", client$settings$model %||% act$arg, "]\n", sep = "")
        }
        TRUE
      },
      FALSE  # prompt / skill fall through
    )
    if (isTRUE(handled)) next

    # --- prompt / skill: run the turn pipeline (mirrors agent_loop) ---
    user_input <- act$text
    if (identical(act$action, "skill")) {
      parsed <- tryCatch(.preprocess_input(user_input, cwd),
                         error = function(e) list(type = "text"))
      if (identical(parsed$type, "skill")) {
        user_input <- tryCatch(load_skill_prompt(parsed$name, parsed$args, cwd),
                               error = function(e) user_input)
      }
    }

    # 1. Compaction + resource management (per turn, like agent_loop)
    tryCatch(compaction_ctrl$maybe_compact(client$chat,
             settings$model_limit %||% 200000L), error = function(e) NULL)
    tryCatch(resource_state$maybe_replace(client$chat), error = function(e) NULL)

    # 2. system-reminder injection (date/iteration/cwd/memory)
    reminder <- tryCatch(.build_system_reminder(settings, iteration, cwd),
                         error = function(e) "")
    actual_input <- if (nzchar(reminder))
      paste0(user_input, "\n\n", reminder) else user_input

    # 3. Stream / send
    ok <- if (isTRUE(stream)) {
      tryCatch({
        s <- client$chat$stream(actual_input)
        # ellmer Chat$stream() yields a coro generator; iterate with coro::loop
        # (base for() can't walk a generator -> "invalid for() loop sequence").
        coro::loop(for (chunk in s) cat(chunk))
        cat("\n"); TRUE
      }, error = function(e) { cat("[error: ", conditionMessage(e), "]\n", sep = ""); FALSE })
    } else {
      resp <- tryCatch(client$chat$chat(actual_input),
                       error = function(e) paste0("[error] ", conditionMessage(e)))
      cat(if (is.character(resp)) resp else "[no response]", "\n"); TRUE
    }

    # 4. Housekeeping: auto-save + budget line
    iteration <- iteration + 1L
    tryCatch(save_session(client$chat, cwd, session_id), error = function(e) NULL)
    if (isTRUE(ok)) .repl_budget_line(client$chat, settings)
  }

  tryCatch(save_session(client$chat, cwd, session_id), error = function(e) NULL)
  cat(sprintf("Session saved: %s\n", substr(session_id, 1L, 8L)))
  invisible(session_id)
}
