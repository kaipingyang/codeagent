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
                     "model", "sessions", "budget", "rewind",
                     "cost", "copy", "export")

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
    cost     = list(action = "cost"),
    copy     = list(action = "copy"),
    export   = list(action = "export", arg = arg),
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
  "  /budget         show token usage vs context window limit",
  "  /cost           show token usage and USD cost for this session",
  "  /copy           copy the last response to clipboard",
  "  /export [path]  export conversation to a Markdown file",
  "  /<skill> [args] invoke a skill (e.g. /plan)",
  "  /help           show this help",
  "  /exit, /quit    leave the REPL",
  "  Ctrl+R          reverse history search",
  "  Ctrl+C Ctrl+C   exit REPL",
  sep = "\n"
)

# Print a one-line token-budget status (only when usage is notable).
.repl_budget_line <- function(chat, settings, force = FALSE) {
  n     <- tryCatch(token_count_with_estimation(chat), error = function(e) 0L)
  model <- settings$model %||% ""
  ws    <- tryCatch(calculate_token_warning_state(n, model),
                    error = function(e) NULL)
  if (is.null(ws)) {
    # No window info: still answer an explicit /budget with the raw token count.
    if (isTRUE(force))
      cat(sprintf("  [%s tokens]\n", format(n, big.mark = ",")))
    return(invisible(NULL))
  }
  left <- ws$percent_left
  # The AUTOMATIC post-turn line only surfaces when context is getting tight, to
  # avoid noise. An explicit `/budget` (force = TRUE) always prints.
  if (!isTRUE(force) && left > 50L && !isTRUE(ws$above_warning))
    return(invisible(NULL))
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

# Animated spinner for the "waiting for first token" phase.
# Returns NULL on non-TTY (pipe/redirect) so callers skip the spinner entirely.
# The spinner uses the later pump loop (100 ms ticks) via on_tick= in
# codeagent_stream(), so it animates even while blocking on the async stream.
.make_cli_spinner <- function(msg = "Thinking") {
  if (!tryCatch(isatty(stdout()), error = function(e) FALSE)) return(NULL)
  frames  <- c("⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏")
  fi      <- 0L
  active  <- TRUE
  list(
    tick = function() {
      if (!active) return(invisible(NULL))
      fi <<- (fi %% length(frames)) + 1L
      cat("\r",
          tryCatch(cli::style_dim(paste0(frames[[fi]], " ", msg, "...")),
                   error = function(e) paste0(frames[[fi]], " ", msg, "...")),
          sep = "")
      utils::flush.console()
    },
    clear = function() {
      if (!active) return(invisible(NULL))
      active <<- FALSE
      cat("\r\033[K")
      utils::flush.console()
    }
  )
}

# ---------------------------------------------------------------------------
# Ctrl+R history search helpers (pure, testable)
# ---------------------------------------------------------------------------

# Update state after search_query changes: find the most recent history entry
# that contains the query string, load it into chars.
.search_update <- function(state) {
  q <- paste(state$search_query, collapse = "")
  if (!nzchar(q)) {
    # Empty query: restore stash
    state$chars <- state$stash
    state$pos   <- length(state$stash)
    return(state)
  }
  idx <- which(grepl(q, state$history, fixed = TRUE))
  if (length(idx)) {
    # Most recent match (highest index = most recent)
    hit <- state$history[[idx[[length(idx)]]]]
    state$chars        <- strsplit(hit, "", fixed = TRUE)[[1L]]
    state$pos          <- length(state$chars)
    state$search_match <- idx[[length(idx)]]   # track for Ctrl+R-again
  }
  state
}

# Ctrl+R pressed again: find the next-older match.
.search_next <- function(state) {
  q <- paste(state$search_query, collapse = "")
  if (!nzchar(q)) return(state)
  idx <- which(grepl(q, state$history, fixed = TRUE))
  if (!length(idx)) return(state)
  cur_match <- state$search_match %||% (length(state$history) + 1L)
  earlier   <- idx[idx < cur_match]
  if (length(earlier)) {
    hit <- state$history[[earlier[[length(earlier)]]]]
    state$chars        <- strsplit(hit, "", fixed = TRUE)[[1L]]
    state$pos          <- length(state$chars)
    state$search_match <- earlier[[length(earlier)]]
  }
  state
}

# Colored, card-style tool lines for the console TUI. cli auto-disables ANSI on
# non-tty / NO_COLOR, so these degrade to plain text (tests see plain strings.
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

  # Shared state for double-Ctrl+C detection: persists last_cancel_time across
  # successive .console_read_line calls within this REPL session.
  cancel_env <- new.env(parent = emptyenv())
  cancel_env$last_cancel_time <- NULL

  # Tool execution visibility: print tool name when a tool is requested, and a
  # one-line summary when it completes.  Mirrors Claude Code's CLI behaviour
  # (tool_use pauses text, shows the tool, resumes).  Registered at most once
  # per chat object via .chat_once() to prevent callback stacking on re-entry.
  if (.chat_once(client$chat, "repl_display"))
    .register_repl_tool_callbacks(client$chat)

  cat("\n")
  ver <- tryCatch(as.character(utils::packageVersion("codeagent")),
                  error = function(e) "0.1.0")
  sid8 <- substr(session_id, 1L, 8L)
  model_str <- settings$model %||% "(auto)"
  mode_str  <- settings$permission_mode %||% "default"

  if (!isTRUE(quiet)) {
    # Codex-style box banner via cli::boxx (round corners, key info aligned).
    branch <- tryCatch({
      if (requireNamespace("gert", quietly = TRUE)) {
        gert::git_branch(repo = cwd)
      } else {
        # No-shell fallback (arg vector, not a shell string).
        b <- system2("git", c("-C", cwd, "rev-parse", "--abbrev-ref", "HEAD"),
                     stdout = TRUE, stderr = FALSE)
        if (length(b)) trimws(b[1]) else ""
      }
    }, error = function(e) "")
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
    ), padding = c(0L, 1L, 0L, 1L), border_style = "round",
       border_col = "cyan")
    cat("\n")

    # Settings completeness check: emit actionable warnings for missing config
    # (API key, base URL) so users see them before the first request fails.
    tryCatch(.check_settings_completeness(settings), error = function(e) NULL)
  }

  history <- character(0)  # in-session line history for up/down recall
  repeat {
    line <- .console_read_line(prompt_str, history, con, cancel_env)
    if (is.null(line)) break  # EOF (Ctrl-D / closed connection)
    if (nzchar(trimws(line))) history <- c(history, line)
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
      budget = { .repl_budget_line(client$chat, settings, force = TRUE); TRUE },
      cost = {
        n     <- tryCatch(token_count_with_estimation(client$chat),
                          error = function(e) 0L)
        last  <- tryCatch(client$chat$get_cost(include = "last"),
                          error = function(e) NA_real_)
        total <- tryCatch(client$chat$get_cost(include = "all"),
                          error = function(e) NA_real_)
        cat(sprintf("  tokens:      %s\n", format(as.integer(n), big.mark = ",")))
        if (!is.na(last))  cat(sprintf("  last turn:   $%.6f\n", last))
        if (!is.na(total)) cat(sprintf("  session:     $%.6f\n", total))
        TRUE
      },
      copy = {
        # Collect all ContentText blocks from the last assistant turn
        last_txt <- tryCatch({
          lt <- client$chat$last_turn()
          parts <- lapply(lt@contents, function(ct)
            tryCatch(ct@text, error = function(e) NULL))
          paste(Filter(nzchar, Filter(Negate(is.null), parts)), collapse = "\n")
        }, error = function(e) NULL)
        if (!is.null(last_txt) && nzchar(last_txt)) {
          if (requireNamespace("clipr", quietly = TRUE)) {
            tryCatch(clipr::write_clip(last_txt), error = function(e) NULL)
            preview <- substr(last_txt, 1L, 60L)
            cat(sprintf("[copied] %.60s%s\n", preview,
                        if (nchar(last_txt) > 60L) "…" else ""))
          } else {
            cat("[clipr not installed — run: install.packages('clipr')]\n")
          }
        } else {
          cat("[nothing to copy]\n")
        }
        TRUE
      },
      export = {
        sid8 <- substr(session_id %||% "unknown", 1L, 8L)
        out_path <- if (nzchar(act$arg %||% "")) act$arg
                    else sprintf("codeagent-session-%s.md", sid8)
        turns <- tryCatch(client$chat$get_turns(), error = function(e) list())
        lines <- c(
          sprintf("# codeagent session %s", sid8),
          sprintf("_exported: %s_\n", format(Sys.time()))
        )
        for (turn in turns) {
          role <- tryCatch(turn@role, error = function(e) "unknown")
          for (ct in tryCatch(turn@contents, error = function(e) list())) {
            txt <- tryCatch(ct@text, error = function(e) NULL)
            if (!is.null(txt) && nzchar(txt))
              lines <- c(lines, sprintf("## %s\n\n%s\n", role, txt))
          }
        }
        tryCatch({
          writeLines(lines, out_path)
          cat(sprintf("[exported to %s]\n", out_path))
        }, error = function(e) {
          cat("[export failed]:", conditionMessage(e), "\n")
        })
        TRUE
      },
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
          cat("Usage: /model <tier-or-endpoint>  e.g. /model main\n")
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

    # 1+2. Compaction + resource management + system-reminder injection
    actual_input <- .turn_setup(client, user_input, iteration, cwd,
                                compaction_ctrl, resource_state)

    # 3. Stream / send (with full error recovery: PTL/rate-limit/network/auth)
    if (isTRUE(stream)) {
      # Animated spinner while waiting for the first token from the model.
      # .make_cli_spinner() returns NULL on non-TTY (pipe/redirect), so the
      # spinner is skipped automatically in scripted / non-interactive usage.
      sp <- .make_cli_spinner()

      result <- codeagent_stream(
        client, actual_input,
        on_tick     = if (!is.null(sp)) sp$tick else NULL,
        on_delta    = function(txt) {
          if (!is.null(sp)) sp$clear()
          cat(txt)
        },
        on_thinking = function(th) {
          if (!is.null(sp)) sp$clear()
          cat(.fmt_thinking(th))
        },
        on_error    = function(msg, rec) {
          if (!is.null(sp)) sp$clear()
          cat(if (nzchar(msg)) msg else "[no response]", "\n")
        },
        on_usage    = function(usage) {
          n  <- usage$n_tokens  %||% 0L
          ws <- usage$warning_state
          if (!is.null(ws)) {
            left <- ws$percent_left
            if (isTRUE(ws$above_warning) || left <= 50L) {
              label <- sprintf("%d%% context left", left)
              label <- if (isTRUE(ws$above_error))
                         tryCatch(cli::col_red(label), error = function(e) label)
                       else if (isTRUE(ws$above_warning))
                         tryCatch(cli::col_yellow(label), error = function(e) label)
                       else label
              cat(sprintf("\n  [%s tokens / %s]\n",
                          format(as.integer(n), big.mark = ","), label))
            }
          }
        },
        session_id      = session_id,
        iteration       = iteration,
        cwd             = cwd,
        compaction_ctrl = compaction_ctrl,
        resource_state  = resource_state)

      if (!is.null(sp)) sp$clear()   # ensure cleared even on error/interrupt
      if (!identical(result$stop_reason, "error")) cat("\n")
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
      cat(if (is.character(resp)) .render_markdown(resp) else "[no response]", "\n")
      # Non-streaming path still needs teardown (save + budget).
      tryCatch(save_session(client$chat, cwd, session_id), error = function(e) NULL)
      .repl_budget_line(client$chat, settings)
    }

    # 4. Housekeeping (streaming path: codeagent_stream already saved session
    # and reported usage via on_usage; non-streaming handled above).
    iteration <- iteration + 1L
  }

  tryCatch(save_session(client$chat, cwd, session_id), error = function(e) NULL)
  cat(sprintf("Session saved: %s\n", substr(session_id, 1L, 8L)))
  invisible(session_id)
}


# ---------------------------------------------------------------------------
# Console line editor
# ---------------------------------------------------------------------------
# The console reads a whole line per turn. Plain readLines() on file("stdin")
# relies on the terminal's cooked mode, which does NOT interpret arrow / Home /
# End / Delete keys -- their escape sequences (e.g. Left = ESC[D) leak into the
# input as literal "^[[D". We instead read one key at a time (keypress pkg,
# which puts the TTY in raw mode) and maintain the line buffer + cursor
# ourselves. Falls back to cooked readLines when there is no keypress support
# (pipes, tests, unsupported terminals).

# Pure key handler: given editor state + a keypress name, return the new state.
# Kept side-effect-free so every key case is unit-testable.
#   state = list(chars = <chars>, pos = <int>, history = <chr>,
#                hist_pos = <int>, stash = <chars>, action = NULL|chr)
.console_apply_key <- function(state, key) {
  n <- length(state$chars)
  load_hist <- function(s, idx) {
    txt <- s$history[idx]
    s$chars <- if (is.na(txt) || !nzchar(txt)) character(0)
               else strsplit(txt, "", fixed = TRUE)[[1]]
    s$pos <- length(s$chars)
    s
  }
  if (isTRUE(state$search_mode)) {
    # Search mode takes priority over all other key handlers
    if (key %in% c("enter", "\r", "\n")) {
      state$search_mode <- FALSE
      state$pos         <- length(state$chars)
      state$action      <- "submit"
    } else if (key == "escape") {
      state$search_mode  <- FALSE
      state$chars        <- state$stash
      state$pos          <- length(state$stash)
      state$search_query <- character(0)
    } else if (key == "ctrl-r") {
      # Ctrl+R again: find next-older match
      state <- .search_next(state)
    } else if (key == "backspace") {
      if (length(state$search_query) > 0L)
        state$search_query <- state$search_query[-length(state$search_query)]
      state <- .search_update(state)
    } else if (nchar(key, type = "chars") == 1L && !grepl("[[:cntrl:]]", key)) {
      state$search_query <- c(state$search_query, key)
      state <- .search_update(state)
    } else {
      # Other keys (arrows, ctrl-*) cancel search mode gracefully
      state$search_mode  <- FALSE
      state$search_query <- character(0)
    }
  } else if (key %in% c("enter", "\r", "\n")) {
    state$action <- "submit"
  } else if (key == "left") {
    state$pos <- max(0L, state$pos - 1L)
  } else if (key == "right") {
    state$pos <- min(n, state$pos + 1L)
  } else if (key %in% c("home", "ctrl-a")) {
    state$pos <- 0L
  } else if (key %in% c("end", "ctrl-e")) {
    state$pos <- n
  } else if (key == "backspace") {
    if (state$pos > 0L) {
      state$chars <- state$chars[-state$pos]
      state$pos   <- state$pos - 1L
    }
  } else if (key == "delete") {
    if (state$pos < n) state$chars <- state$chars[-(state$pos + 1L)]
  } else if (key == "ctrl-u") {          # kill to line start
    if (state$pos > 0L) state$chars <- state$chars[-seq_len(state$pos)]
    state$pos <- 0L
  } else if (key == "ctrl-k") {          # kill to line end
    if (state$pos < n) state$chars <- state$chars[seq_len(state$pos)]
  } else if (key == "ctrl-c") {
    now <- proc.time()[["elapsed"]]
    if (!is.null(state$last_cancel_time) &&
        (now - state$last_cancel_time) < 1.5) {
      # Double Ctrl+C within 1.5s -> exit the REPL
      state$action <- "exit"
    } else {
      state$last_cancel_time <- now
      state$action <- "cancel"
    }
  } else if (key == "ctrl-d") {
    if (n == 0L) state$action <- "eof"   # EOF only on an empty line
  } else if (key == "up") {
    if (state$hist_pos > 1L) {
      if (state$hist_pos == length(state$history) + 1L) state$stash <- state$chars
      state$hist_pos <- state$hist_pos - 1L
      state <- load_hist(state, state$hist_pos)
    }
  } else if (key == "down") {
    if (state$hist_pos <= length(state$history)) {
      state$hist_pos <- state$hist_pos + 1L
      if (state$hist_pos == length(state$history) + 1L) {
        state$chars <- state$stash
        state$pos   <- length(state$chars)
      } else {
        state <- load_hist(state, state$hist_pos)
      }
    }
  } else if (key == "ctrl-r") {
    # Enter search mode (search_mode=TRUE case handled at top)
    state$search_mode  <- TRUE
    state$search_query <- character(0)
    state$search_match <- length(state$history) + 1L
    state$stash        <- state$chars  # save current line
  } else if (key %in% c("tab", "escape", "insert", "pageup", "pagedown") ||
             startsWith(key, "ctrl-") ||
             (startsWith(key, "f") && nchar(key) > 1L)) {
    # ignore unsupported specials (no-op) rather than inserting garbage
    # note: "f" alone is the printable letter f; "f1".."f12" are function keys
  } else if (nchar(key, type = "chars") == 1L && !grepl("[[:cntrl:]]", key)) {
    # printable single character -> insert at cursor
    state$chars <- append(state$chars, key, after = state$pos)
    state$pos   <- state$pos + 1L
  }
  state
}

# Redraw the current line in place: carriage-return, clear to EOL, reprint
# prompt + buffer, then move the cursor back to its logical position.
.console_redraw <- function(prompt, state) {
  line <- paste(state$chars, collapse = "")
  if (isTRUE(state$search_mode)) {
    q           <- paste(state$search_query, collapse = "")
    search_pfx  <- tryCatch(
      cli::style_dim(sprintf("(reverse-i-search)`%s': ", q)),
      error = function(e) sprintf("(reverse-i-search)`%s': ", q))
    cat("\r\033[K", search_pfx, line, sep = "")
  } else {
    cat("\r\033[K", prompt, line, sep = "")
  }
  back <- length(state$chars) - state$pos
  if (back > 0L) cat(sprintf("\033[%dD", back))
  utils::flush.console()
}

# Read one edited line. Returns the string, "" for a cancelled (Ctrl-C) line,
# or NULL on EOF (Ctrl-D on empty line / closed connection).
# cancel_env: an environment with a $last_cancel_time field, shared across
# calls from the same REPL session so double-Ctrl+C can be detected.
.console_read_line <- function(prompt, history = character(0), con = stdin(),
                                cancel_env = new.env(parent = emptyenv())) {
  supported <- tryCatch(keypress::has_keypress_support(), error = function(e) FALSE)
  if (!isTRUE(supported)) {
    # Cooked-mode fallback (pipes, tests, unsupported terminals).
    cat(prompt)
    line <- tryCatch(readLines(con, n = 1L), error = function(e) character(0))
    if (length(line) == 0L) return(NULL)
    return(line[[1]])
  }
  state <- list(chars = character(0), pos = 0L, history = history,
                hist_pos = length(history) + 1L, stash = character(0),
                action = NULL,
                last_cancel_time = cancel_env$last_cancel_time,
                search_mode  = FALSE,
                search_query = character(0),
                search_match = NULL)
  .console_redraw(prompt, state)
  repeat {
    key <- tryCatch(keypress::keypress(), error = function(e) "enter")
    state <- .console_apply_key(state, key)
    # Persist last_cancel_time back to the shared env so it survives
    # across successive _console_read_line calls within the same session.
    cancel_env$last_cancel_time <- state$last_cancel_time
    .console_redraw(prompt, state)
    if (!is.null(state$action)) break
  }
  cat("\n")
  switch(state$action,
    eof    = NULL,
    exit   = NULL,   # double Ctrl+C -> exit REPL
    cancel = "",
    paste(state$chars, collapse = "")
  )
}
