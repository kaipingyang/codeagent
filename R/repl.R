#' @title Interactive CLI REPL (harness, no Shiny)
#' @description A terminal read-eval-print loop for the agent. Reuses one
#'   `CodeagentClient` so history accumulates in the Chat object across turns.
#'   Mirrors the Shiny `agent_loop()` turn pipeline so long sessions stay
#'   healthy: per-turn compaction, `<system-reminder>` injection, skill
#'   preprocessing, and auto-save -- the same harness objects the app uses.
#'
#'   Slash commands: `/model`, `/compact`, `/clear`, `/sessions`, `/budget`,
#'   `/help`, `/exit`. `/<skill>` invokes a skill via `load_skill_prompt()`.
#'   The line parser `.repl_dispatch()` is a pure function (testable); the loop
#'   `codeagent_console()` handles IO + the turn pipeline.
#' @name repl
#' @keywords internal
NULL

# Built-in REPL meta-commands (everything else starting with "/" is a skill).
.REPL_META_CMDS <- c("exit", "quit", "help", "clear", "compact",
                     "model", "sessions", "budget", "rewind")

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
    compact  = list(action = "compact", arg = arg),
    sessions = list(action = "sessions"),
    budget   = list(action = "budget"),
    rewind   = list(action = "rewind", arg = arg),
    model    = list(action = "model", arg = arg)
  )
}

.repl_help <- paste(
  "Commands:",
  "  /model [spec]   show current model & tiers; /model <name> to switch",
  "  /compact [hint] force context compaction (optional focus instructions)",
  "  /clear          clear conversation history",
  "  /rewind [N]     drop the last N exchanges (default 1)",
  "  /sessions       list recent saved sessions",
  "  /budget         show token usage vs limit",
  "  /<skill> [args] invoke a skill (e.g. /plan)",
  "  /help           show this help",
  "  /exit, /quit    leave the REPL",
  sep = "\n"
)

# Print a one-line token-budget status (only when usage is notable).
.repl_budget_line <- function(chat, settings) {
  n     <- tryCatch(token_count_with_estimation(chat), error = function(e) 0L)
  model <- settings$model %||% ""
  ws    <- tryCatch(calculate_token_warning_state(n, model),
                    error = function(e) NULL)
  if (is.null(ws)) return(invisible(NULL))
  left <- ws$percent_left
  # Only surface when context is getting tight or a warning line is crossed.
  if (left > 50L && !isTRUE(ws$above_warning)) return(invisible(NULL))
  label <- sprintf("%d%% context left", left)
  label <- if (isTRUE(ws$above_error))
             tryCatch(cli::col_red(label), error = function(e) label)
           else if (isTRUE(ws$above_warning))
             tryCatch(cli::col_yellow(label), error = function(e) label)
           else label
  cat(sprintf("  [%s tokens / %s]\n", format(n, big.mark = ","), label))
  invisible(NULL)
}

# Summarise a tool result for the one-line completion notice.
# Prefers the typed display title; falls back to a char count of the value.
.repl_tool_summary <- function(result) {
  disp <- tryCatch(result@extra$display, error = function(e) NULL)
  title <- tryCatch(
    disp$toolcard$title %||% gsub("<[^>]+>", "", as.character(disp$title %||% "")),
    error = function(e) ""
  )
  if (!is.null(title) && nzchar(title)) return(trimws(title))
  val <- tryCatch(as.character(result@value), error = function(e) "")
  if (length(val) && nzchar(val[[1L]]))
    return(sprintf("%d chars", nchar(paste(val, collapse = ""))))
  "done"
}

# Derive a human-readable tool label. codeagent registers builtins under
# generic ellmer names (tool_001, ...), so when the name is generic we infer a
# label from which argument is present (command -> Bash, file_path -> file op).
.repl_tool_label <- function(name, args) {
  if (!is.null(name) && nzchar(name) && !grepl("^tool_[0-9]+$", name))
    return(name)
  if (is.list(args)) {
    if (!is.null(args[["command"]]))   return("Bash")
    if (!is.null(args[["file_path"]])) return("File")
    if (!is.null(args[["pattern"]]))   return("Search")
    if (!is.null(args[["path"]]))      return("Path")
  }
  name %||% "tool"
}

# Colored, card-style tool lines for the console TUI. cli auto-disables ANSI on
# non-tty / NO_COLOR, so these degrade to plain text (tests see plain strings).
#   request:  ⏺ <label>  <hint>     (cyan bold label, dim hint)
#   result:     ⎿ <summary>          (green connector, dim text)
.repl_tool_request_line <- function(label, hint = "") {
  glyph <- tryCatch(cli::col_cyan("\u23fa"), error = function(e) "*")
  lab   <- tryCatch(cli::col_cyan(cli::style_bold(label)), error = function(e) label)
  h     <- if (nzchar(hint)) tryCatch(cli::style_dim(paste0("  ", hint)),
                                      error = function(e) paste0("  ", hint)) else ""
  paste0("\n", glyph, " ", lab, h, "\n")
}
.repl_tool_result_line <- function(summary) {
  conn <- tryCatch(cli::col_green("\u23bf"), error = function(e) "->")
  txt  <- tryCatch(cli::style_dim(summary), error = function(e) summary)
  paste0("    ", conn, " ", txt, "\n")
}

# Register tool-visibility callbacks on the Chat (idempotent per chat object).
# on_tool_request -> print the tool name (so tool_use is visible mid-stream);
# on_tool_result  -> print a one-line summary.  Mirrors Claude Code's CLI.
.register_repl_tool_callbacks <- function(chat) {
  ok_req <- tryCatch({
    chat$on_tool_request(function(request) {
      nm   <- tryCatch(request@name, error = function(e) NULL)
      args <- tryCatch(request@arguments, error = function(e) NULL)
      label <- .repl_tool_label(nm, args)
      # Show the most identifying argument inline when cheap to compute.
      hint <- tryCatch({
        a <- args[["command"]] %||% args[["file_path"]] %||%
             args[["pattern"]] %||% args[["path"]] %||% ""
        a <- as.character(a)[[1L]] %||% ""
        if (nzchar(a)) substr(a, 1L, 60L) else ""
      }, error = function(e) "")
      cat(.repl_tool_request_line(label, hint))
    })
    TRUE
  }, error = function(e) FALSE)

  tryCatch({
    chat$on_tool_result(function(result) {
      cat(.repl_tool_result_line(.repl_tool_summary(result)))
    })
  }, error = function(e) NULL)

  invisible(ok_req)
}

# Extract printable text from a stream="content" chunk. ellmer yields S7
# Content objects (ContentText / ContentThinking / tool content); for plain
# text we want @text. Falls back to as.character for raw string chunks.
.chunk_text <- function(chunk) {
  if (is.character(chunk)) return(chunk)
  txt <- tryCatch(chunk@text, error = function(e) NULL)
  if (!is.null(txt) && is.character(txt)) return(paste(txt, collapse = ""))
  ""
}

# Format a thinking/reasoning block for the terminal (ANSI dim).  Only models
# that emit extended thinking produce these; otherwise this is never called.
.fmt_thinking <- function(text) {
  if (is.null(text) || !nzchar(text)) return("")
  # \033[2m = dim, \033[0m = reset
  paste0("\033[2m", text, "\033[0m")
}

# ---------------------------------------------------------------------------
# Terminal markdown rendering (fenced code + light styling)
# ---------------------------------------------------------------------------
# Renders a useful subset of markdown for the console: fenced code blocks
# (R highlighted via {prettycode} when available, else dimmed), ATX headers,
# **bold**, and `inline code`. ANSI is only emitted on a colour-capable tty, so
# captured/piped output stays plain.
.render_code_block <- function(code, lang, use_color) {
  lang_l <- tolower(lang)
  body <- if (lang_l %in% c("r", "rscript", "") &&
              requireNamespace("prettycode", quietly = TRUE) && use_color) {
    tryCatch(as.character(prettycode::highlight(code)), error = function(e) code)
  } else if (use_color) {
    paste0("\033[2m", code, "\033[0m")   # dim non-R (or no prettycode)
  } else {
    code
  }
  bar <- if (use_color) "\u001b[90m\u2502\u001b[0m" else "|"   # grey left bar
  tag <- if (nzchar(lang)) lang else "code"
  head <- if (use_color) paste0("  ", bar, " \033[90m", tag, "\033[0m")
          else paste0("  ", bar, " ", tag)
  c(head, paste0("  ", bar, " ", body))
}

.render_md_line <- function(ln, use_color) {
  if (grepl("^#{1,6}\\s", ln)) {
    h <- sub("^#{1,6}\\s+", "", ln)
    return(if (use_color) paste0("\033[1m", h, "\033[0m") else h)
  }
  if (use_color) {
    ln <- gsub("`([^`]+)`", "\033[36m\\1\033[39m", ln)        # inline code -> cyan
    ln <- gsub("\\*\\*([^*]+)\\*\\*", "\033[1m\\1\033[0m", ln)  # **bold**
  }
  ln
}

#' Render a subset of markdown for the terminal.
#' @param text Character scalar (assistant response).
#' @return Character scalar with fenced code highlighted + light styling.
#' @keywords internal
.render_markdown <- function(text) {
  if (is.null(text) || !length(text) || !nzchar(text[[1L]])) return(text %||% "")
  use_color <- tryCatch(cli::num_ansi_colors() > 1L, error = function(e) FALSE)
  lines <- strsplit(paste(text, collapse = "\n"), "\n", fixed = TRUE)[[1L]]
  out <- character(0); i <- 1L; n <- length(lines)
  while (i <= n) {
    ln <- lines[[i]]
    if (grepl("^```", ln)) {
      lang <- sub("^```[[:space:]]*", "", sub("[[:space:]]*$", "", ln))
      j <- i + 1L; code <- character(0)
      while (j <= n && !grepl("^```[[:space:]]*$", lines[[j]])) {
        code <- c(code, lines[[j]]); j <- j + 1L
      }
      out <- c(out, .render_code_block(code, lang, use_color))
      i <- j + 1L
    } else {
      out <- c(out, .render_md_line(ln, use_color))
      i <- i + 1L
    }
  }
  paste(out, collapse = "\n")
}

#' Run the interactive REPL
#'
#' @param client A `CodeagentClient`.
#' @param stream Logical. Stream responses token-by-token.
#' @param prompt_str Character. The input prompt shown each turn.
#' @param con Connection to read lines from (default stdin; override in tests).
#' @param session_id Character or NULL. Session id for auto-save (generated if
#'   NULL).
#' @param quiet Logical. Suppress the startup banner and settings warnings
#'   (used in tests and non-interactive contexts where the output would be
#'   noise).
#' @return Invisibly the session id. Loops until `/exit` or EOF.
#' @export
codeagent_console <- function(client, stream = TRUE, prompt_str = "\u203a ",
                           con = NULL, session_id = NULL, quiet = FALSE) {
  if (!inherits(client, "CodeagentClient"))
    stop("codeagent_console() expects a CodeagentClient.", call. = FALSE)

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

  # Tool execution visibility: print tool name when a tool is requested, and a
  # one-line summary when it completes.  Mirrors Claude Code's CLI behaviour
  # (tool_use pauses text, shows the tool, resumes).  Registered once.
  .register_repl_tool_callbacks(client$chat)

  cat("\n")
  ver <- tryCatch(as.character(utils::packageVersion("codeagent")),
                  error = function(e) "0.1.0")
  sid8 <- substr(session_id, 1L, 8L)
  model_str <- settings$model %||% "(auto)"
  mode_str  <- settings$permission_mode %||% "default"

  if (!isTRUE(quiet)) {
    # Codex-style box banner via cli::boxx (round corners, key info aligned).
    branch <- tryCatch(
      trimws(system("git rev-parse --abbrev-ref HEAD 2>/dev/null", intern = TRUE,
                    ignore.stderr = TRUE)),
      error = function(e) "")
    short_cwd <- if (nchar(cwd) > 48)
      paste0("...", substr(cwd, nchar(cwd) - 44L, nchar(cwd))) else cwd
    dir_str <- if (nzchar(branch)) paste0(short_cwd, "  (", branch, ")")
               else short_cwd
    effort_str <- settings$effort_level %||% settings$effortLevel %||% ""
    model_line <- paste0("model:     ", model_str,
                         if (nzchar(effort_str)) paste0("  ", effort_str) else "",
                         "   /model to change")
    cli::cat_boxx(c(
      paste0(">_ codeagent ", ver),
      "",
      model_line,
      paste0("mode:      ", mode_str, "      session: ", sid8),
      paste0("directory: ", dir_str)
    ), padding = c(0L, 1L, 0L, 1L), border_style = "round")
    cat("\n")

    # Settings completeness check: emit actionable warnings for missing config
    # (API key, base URL) so users see them before the first request fails.
    tryCatch(.check_settings_completeness(settings), error = function(e) NULL)
  }

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
        instr <- trimws(parsed$arg %||% "")
        tryCatch(full_compact(client$chat,
                              model = .resolve_compact_model(client$chat, settings),
                              instructions = if (nzchar(instr)) instr else NULL),
                 error = function(e)
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
      rewind = {
        # Drop the last N exchanges (default 1). One exchange = 2 turns
        # (user + assistant), so keep = current_turns - 2*N.
        n_back <- suppressWarnings(as.integer(act$arg))
        if (is.na(n_back) || n_back < 1L) n_back <- 1L
        cur  <- length(tryCatch(client$chat$get_turns(), error = function(e) list()))
        keep <- max(0L, cur - 2L * n_back)
        kept <- tryCatch(truncate_chat_turns(client$chat, keep),
                         error = function(e) cur)
        tryCatch(save_session(client$chat, cwd, session_id), error = function(e) NULL)
        cat(sprintf("[rewound %d exchange(s); %d turns kept]\n", n_back, kept))
        TRUE
      },
      model = {
        if (!nzchar(act$arg)) {
          # No arg: show current model and available tiers
          cur <- settings$model %||% "(auto)"
          cat(sprintf("Current model: %s\n", cur))
          tiers <- tryCatch(settings$tier_models, error = function(e) list())
          if (length(tiers)) {
            cat("Available tiers (use /model <name>):\n")
            for (nm in names(tiers))
              cat(sprintf("  %-10s -> %s%s\n", nm, tiers[[nm]],
                          if (identical(tiers[[nm]], cur)) "  (active)" else ""))
          }
          cat("Usage: /model <tier-or-endpoint>  e.g. /model sonnet\n")
        } else {
          client <- tryCatch(switch_model(client, act$arg), error = function(e) {
            cat("[model switch failed: ", conditionMessage(e), "]\n", sep = ""); client
          })
          cat("[model: ", client$settings$model %||% act$arg, "]\n", sep = "")
          # Keep settings in sync so banner + next turn see new model
          settings <- client$settings
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
             settings$model_limit %||% 200000L,
             compact_model = .resolve_compact_model(client$chat, settings)),
             error = function(e) NULL)
    tryCatch(resource_state$maybe_replace(client$chat), error = function(e) NULL)

    # 2. system-reminder injection (date/iteration/cwd/memory)
    reminder <- tryCatch(.build_system_reminder(settings, iteration, cwd,
                                                query = user_input),
                         error = function(e) "")
    actual_input <- if (nzchar(reminder))
      paste0(user_input, "\n\n", reminder) else user_input

    # 3. Stream / send (with full error recovery: PTL/rate-limit/network/auth)
    ok <- if (isTRUE(stream)) {
      tryCatch({
        # stream="content" yields S7 Content objects (ContentText /
        # ContentThinking) instead of raw strings, so reasoning blocks can be
        # rendered distinctly. Models without extended thinking only emit
        # ContentText -> identical output to before.
        s <- client$chat$stream(actual_input, stream = "content")
        # Progress: show a dim "thinking" hint during the initial latency, then
        # clear it (\r + erase-line) as soon as the first token arrives. TTY-only
        # so piped/non-interactive output stays clean.
        show_hint   <- tryCatch(isatty(stdout()), error = function(e) FALSE)
        hint_active <- FALSE
        if (show_hint) {
          cat(tryCatch(cli::style_dim("\u22ef thinking"),
                       error = function(e) "... thinking"))
          hint_active <- TRUE
        }
        first_chunk <- TRUE
        coro::loop(for (chunk in s) {
          if (hint_active) { cat("\r\033[K"); hint_active <- FALSE }
          if (S7::S7_inherits(chunk, ellmer::ContentThinking)) {
            th <- tryCatch(chunk@thinking, error = function(e) "")
            cat(.fmt_thinking(th))
            first_chunk <- FALSE
          } else {
            txt <- .chunk_text(chunk)
            if (nzchar(txt)) {
              cat(txt)
              first_chunk <- FALSE
            }
          }
        })
        if (hint_active) cat("\r\033[K")
        cat("\n"); TRUE
      }, error = function(e) {
        recovered <- tryCatch(
          .handle_agent_error(e, client$chat, actual_input, compaction_ctrl),
          error = function(e2) paste0("[error] ", conditionMessage(e2))
        )
        cat(if (is.character(recovered)) recovered else "[no response]", "\n")
        TRUE
      })
    } else {
      # Non-streaming: spinner while waiting for the response.
      resp <- NULL
      tryCatch({
        sp <- cli::cli_progress_step("Thinking...", spinner = TRUE)
        resp <- tryCatch(client$chat$chat(actual_input),
                         error = function(e)
                           .handle_agent_error(e, client$chat, actual_input, compaction_ctrl))
        cli::cli_progress_done(id = sp)
      }, error = function(e)
        resp <<- tryCatch(client$chat$chat(actual_input),
                          error = function(e2)
                            .handle_agent_error(e2, client$chat, actual_input, compaction_ctrl)))
      cat(if (is.character(resp)) .render_markdown(resp) else "[no response]", "\n"); TRUE
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
