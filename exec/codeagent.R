#!/usr/bin/env Rapp
#| name: codeagent
#| description: >
#|   R-native coding agent built on ellmer. Run interactive sessions, launch
#|   the Shiny app, manage skills, and start an MCP server.
#|
#|   Usage:
#|     codeagent                      # start interactive REPL (default mode)
#|     codeagent -y                   # bypass mode REPL
#|     codeagent "your query"         # one-shot query
#|     codeagent -p "your query"      # one-shot (non-interactive, print)
#|     codeagent -p "query" -o json   # one-shot with JSON output
#|     echo "context" | codeagent -p "explain" # stdin appended as <stdin> block
#|     codeagent -                    # read prompt from stdin
#|     codeagent sessions list        # show saved sessions
#|     codeagent sessions resume      # resume a session (interactive picker)
#| launcher:
#|   default-packages: [base, datasets, utils, stats, methods, codeagent]
#|   vanilla: true

# ---------------------------------------------------------------------------
# Global options (visible to ALL subcommands via Rapp scoping)
# ---------------------------------------------------------------------------

#| description: Print codeagent version and exit.
version <- FALSE

if (version) {
  cat(format(utils::packageVersion("codeagent")), "\n")
  quit(status = 0)
}

#| description: >
#|   Skip all permission prompts (bypass mode). Unsafe outside trusted
#|   environments. Equivalent to --dangerously-skip-permissions in Claude Code.
#| short: 'y'
yolo <- FALSE

#| description: Model override / alias (e.g. openai/gpt-4.1).
#| short: 'm'
model <- ""

#| description: Continue the most recent session (preserve history).
#| short: 'c'
continue <- FALSE

#| description: Resume a specific session by id (preserve history).
resume <- ""

#| description: Stream the response token-by-token to stdout.
#| short: 's'
stream <- FALSE

#| description: Print response and exit (non-interactive / one-shot mode).
#| short: 'p'
print_mode <- FALSE

#| description: >
#|   Output format for -p/--print-mode: "text" (default) or "json".
#|   "json" emits {"response": "...", "session_id": "..."}.
#| short: 'o'
output_format <- "text"

#| description: Override the system prompt for this session.
system_prompt <- ""

#| description: Append text to the default system prompt for this session.
append_system_prompt <- ""

#| description: >
#|   Prompt text for one-shot mode.  Pass "-" to read from stdin.
#|   When no subcommand is given and a prompt is provided (or -p is set),
#|   codeagent runs a single query and exits.
#|   When no prompt and no subcommand, codeagent starts the REPL.
#| required: false
`prompt...` <- c()

# Resolve permission mode once for all subcommands.
.mode <- if (isTRUE(yolo)) "bypass" else "default"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

ca_error <- function(e) {
  msg <- cli::ansi_strip(conditionMessage(e))
  cat(msg, "\n", file = stderr())
  quit(status = 1)
}

ca_output <- function(x, output_fmt = "text", session_id = NULL) {
  codeagent:::.ca_format_output(x, output_fmt = output_fmt, session_id = session_id)
}

ca_self_help <- function(...) {
  script_path <- commandArgs(TRUE)[1]
  Rapp:::print_app_help(script_path, yaml = FALSE, command_path = c(...))
  quit(status = 1)
}

# Build client from env vars (CODEAGENT_BASE_URL / CODEAGENT_API_KEY).
ca_make_client <- function(permission_mode = "default",
                            btw_groups = NULL) {
  sp <- cli::cli_progress_step(
    "Starting codeagent (registering tools and scanning skills…",
    .envir = parent.frame()
  )
  on.exit(tryCatch(cli::cli_progress_done(id = sp), error = function(e) NULL),
          add = TRUE)
  tryCatch(
    codeagent_client(permission_mode = permission_mode, btw_groups = btw_groups),
    error = function(e) {
      cat("[Error] Could not build codeagent client:", conditionMessage(e), "\n",
          file = stderr())
      quit(status = 1)
    }
  )
}

# Apply --system-prompt / --append-system-prompt to a client (in-place).
ca_apply_system_prompt <- function(client, sp, asp) {
  if (nzchar(sp)) {
    tryCatch(client$chat$set_system_prompt(sp), error = function(e) NULL)
  } else if (nzchar(asp)) {
    cur <- tryCatch(client$chat$get_system_prompt() %||% "", error = function(e) "")
    tryCatch(client$chat$set_system_prompt(paste0(cur, "\n\n", asp)),
             error = function(e) NULL)
  }
  invisible(client)
}

# Read prompt from stdin (blocking).  Returns "" on error or empty stdin.
ca_read_stdin <- function() {
  tryCatch(paste(readLines(file("stdin"), warn = FALSE), collapse = "\n"),
           error = function(e) "")
}

# Shared REPL launcher.
ca_start_repl <- function(mode, model, continue, no_stream,
                           sp = "", asp = "") {
  tryCatch({
    client <- ca_make_client(permission_mode = mode)
    ca_apply_system_prompt(client, sp, asp)
    if (nzchar(model))
      client <- codeagent::switch_model(client, model)
    sid <- NULL
    if (isTRUE(continue)) {
      sid <- codeagent::restore_session_into_chat(
        client$chat, session_id = NULL, cwd = getwd())
      if (!is.null(sid))
        cat("[continued session ", substr(sid, 1L, 8L), "]\n", sep = "")
    }
    codeagent::codeagent_console(client, stream = !isTRUE(no_stream),
                                 session_id = sid)
  }, error = ca_error)
}

# One-shot runner.
ca_run_once <- function(prompt_str, mode, model, continue, resume, stream,
                         output_fmt = "text", sp = "", asp = "") {
  # Stdin handling (Codex-style):
  #   "-" as prompt -> read full stdin as prompt
  #   piped stdin + non-empty prompt -> append stdin as <stdin> block
  #   piped stdin + empty prompt -> use stdin as prompt
  stdin_piped <- !isatty(stdin())
  if (identical(trimws(prompt_str), "-")) {
    prompt_str <- ca_read_stdin()
  } else if (stdin_piped && nzchar(prompt_str)) {
    piped <- ca_read_stdin()
    if (nzchar(piped))
      prompt_str <- paste0(prompt_str, "\n\n<stdin>\n", piped, "\n</stdin>")
  } else if (stdin_piped && !nzchar(prompt_str)) {
    prompt_str <- ca_read_stdin()
  }

  if (!nzchar(prompt_str)) {
    cat("Usage: codeagent run <prompt>  (or pipe input via stdin)\n",
        file = stderr())
    quit(status = 1)
  }

  tryCatch({
    client <- ca_make_client(permission_mode = mode)
    ca_apply_system_prompt(client, sp, asp)
    if (nzchar(model))
      client <- codeagent::switch_model(client, model)
    sid <- NULL
    if (isTRUE(continue) || nzchar(resume)) {
      id  <- if (nzchar(resume)) resume else NULL
      sid <- codeagent::restore_session_into_chat(client$chat,
                                                   session_id = id, cwd = getwd())
      if (is.null(sid))
        cat("[info] no prior session to continue; starting fresh.\n", file = stderr())
    }
    if (isTRUE(stream)) {
      s <- client$chat$stream(prompt_str)
      for (chunk in s) cat(chunk)
      cat("\n")
    } else {
      resp <- codeagent(client, prompt_str)
      ca_output(resp, output_fmt = output_fmt, session_id = sid)
    }
  }, error = ca_error)
}

# ---------------------------------------------------------------------------
# Subcommand dispatch
# ---------------------------------------------------------------------------

#| required: false
switch(
  cmd <- "chat",

  # run -- one-shot query ---------------------------------------------------
  run = {
    prompt_str <- paste(`prompt...`, collapse = " ")
    ca_run_once(prompt_str, .mode, model, continue, resume, stream,
                output_fmt = output_format,
                sp = system_prompt, asp = append_system_prompt)
  },

  # chat -- interactive REPL (default subcommand) ---------------------------
  chat = {
    ca_start_repl(.mode, model, continue, no_stream = !isTRUE(stream),
                  sp = system_prompt, asp = append_system_prompt)
  },

  # repl -- alias for chat --------------------------------------------------
  repl = {
    ca_start_repl(.mode, model, continue, no_stream = !isTRUE(stream),
                  sp = system_prompt, asp = append_system_prompt)
  },

  # app -- launch Shiny UI --------------------------------------------------
  app = {
    #| description: 'UI theme - default, flatly, darkly, or glass.'
    #| short: 't'
    theme <- "default"

    #| description: Port number (0 = random available port).
    port <- 0L

    #| description: Skills to pin at top of sidebar (comma-separated names).
    pinned <- ""

    tryCatch({
      client   <- ca_make_client(permission_mode = .mode)
      ca_apply_system_prompt(client, system_prompt, append_system_prompt)
      pinned_v <- if (nzchar(pinned)) trimws(strsplit(pinned, ",")[[1L]]) else character(0)
      port_val <- if (port == 0L) NULL else port
      codeagent_app(client, pinned_skills = pinned_v, theme = theme,
                    port = port_val)
    }, error = ca_error)
  },

  # sessions -- session management ------------------------------------------
  sessions = {
    switch(
      sessions_cmd <- "",

      # sessions list ----
      list = {
        tryCatch({
          sl <- list_sessions(getwd(), limit = 20L)
          if (!length(sl)) {
            cat("(no saved sessions)\n")
          } else {
            for (s in sl)
              cat(sprintf("  %s  %s\n",
                          substr(s$session_id, 1L, 8L),
                          s$title %||% s$timestamp %||% ""))
          }
        }, error = ca_error)
      },

      # sessions resume ----
      resume = {
        #| description: Session id to resume (omit for interactive picker).
        #| required: false
        `id...` <- c()

        tryCatch({
          id_str <- paste(`id...`, collapse = "")
          client <- ca_make_client(permission_mode = .mode)
          ca_apply_system_prompt(client, system_prompt, append_system_prompt)
          if (nzchar(model)) client <- codeagent::switch_model(client, model)

          if (nzchar(id_str)) {
            # Direct id (allow partial 8-char prefix)
            sid <- codeagent::restore_session_into_chat(
              client$chat, session_id = id_str, cwd = getwd())
            if (is.null(sid))
              stop("Session '", id_str, "' not found.", call. = FALSE)
          } else {
            # Interactive picker
            sl <- list_sessions(getwd(), limit = 20L)
            if (!length(sl)) { cat("No saved sessions.\n"); quit(status = 0) }
            labels <- vapply(sl, function(s)
              sprintf("%s  %s", substr(s$session_id, 1L, 8L),
                      s$title %||% s$timestamp %||% ""), character(1))
            choice <- utils::menu(labels, title = "Resume session:")
            if (choice == 0L) quit(status = 0)
            id_str <- sl[[choice]]$session_id
            sid <- codeagent::restore_session_into_chat(
              client$chat, session_id = id_str, cwd = getwd())
          }
          cat("[resumed session ", substr(id_str, 1L, 8L), "]\n", sep = "")
          codeagent::codeagent_console(client, session_id = sid)
        }, error = ca_error)
      },

      # sessions delete ----
      delete = {
        #| description: Session id (or 8-char prefix) to delete.
        #| required: false
        `id...` <- c()

        tryCatch({
          id_str <- paste(`id...`, collapse = "")
          if (!nzchar(id_str)) {
            cat("Usage: codeagent sessions delete <id>\n", file = stderr())
            quit(status = 1)
          }
          session_dir <- codeagent:::.get_project_session_dir(getwd())
          f <- file.path(session_dir, paste0(id_str, ".jsonl"))
          if (!file.exists(f)) {
            # Try partial (8-char prefix) match
            all <- list.files(session_dir, pattern = "\\.jsonl$", full.names = FALSE)
            matches <- all[startsWith(all, id_str)]
            if (length(matches) == 1L)
              f <- file.path(session_dir, matches)
            else if (length(matches) > 1L)
              stop("Ambiguous id prefix '", id_str, "' -- be more specific.",
                   call. = FALSE)
          }
          if (file.exists(f)) {
            unlink(f)
            cat("Deleted:", basename(f), "\n")
          } else {
            cat("Session not found:", id_str, "\n", file = stderr())
            quit(status = 1)
          }
        }, error = ca_error)
      }
    )
    if (sessions_cmd == "") ca_self_help("sessions")
  },

  # skills -- skill management ----------------------------------------------
  skills = {
    switch(
      skills_cmd <- "",

      # skills list ----
      list = {
        tryCatch({
          metas <- list_skills_meta()
          if (length(metas) == 0L) {
            cat("No skills installed.\n")
          } else {
            for (m in metas)
              cat(sprintf("  /%s -- %s\n", m$name, m$description %||% ""))
          }
        }, error = ca_error)
      },

      # skills install ----
      install = {
        #| description: R package to install skill from.
        package <- NULL

        #| description: Specific skill name to install (optional).
        #| short: 'n'
        name <- ""

        #| description: 'Scope: project (default) or user.'
        scope <- "project"

        if (!requireNamespace("btw", quietly = TRUE)) {
          cat("btw package required for skill installation.\n", file = stderr())
          quit(status = 1)
        }
        tryCatch({
          btw::btw_skill_install_package(
            package,
            skill = if (nzchar(name)) name else NULL,
            scope = scope
          )
          cat(sprintf("Skill installed from '%s' (scope: %s).\n", package, scope))
        }, error = ca_error)
      }
    )
    if (skills_cmd == "") ca_self_help("skills")
  },

  # mcp -- start MCP server -------------------------------------------------
  mcp = {
    #| description: btw tool groups to expose (comma-separated, default all).
    groups <- ""

    tryCatch({
      grps <- if (nzchar(groups)) trimws(strsplit(groups, ",")[[1L]]) else NULL
      codeagent_mcp_server(
        tools = if (!is.null(grps)) btw::btw_tools(grps) else NULL
      )
    }, error = ca_error)
  },

  # info -- show current configuration --------------------------------------
  info = {
    #| description: Output as JSON.
    json <- FALSE

    tryCatch({
      s <- load_settings()
      info <- list(
        model           = s$model,
        permission_mode = s$permission_mode,
        base_url        = s$base_url %||% "(anthropic)",
        max_turns       = s$max_turns,
        cwd             = getwd(),
        skills          = names(list_skills_meta())
      )
      if (json) {
        cat(jsonlite::toJSON(info, auto_unbox = TRUE, pretty = TRUE), "\n")
      } else {
        for (nm in names(info)) {
          val <- info[[nm]]
          if (length(val) > 1L) val <- paste(val, collapse = ", ")
          cat(sprintf("  %-18s %s\n", paste0(nm, ":"), val))
        }
      }
    }, error = ca_error)
  }
)

# ---------------------------------------------------------------------------
# Bare-prompt / print-mode / piped-stdin fallback
# When no subcommand was matched (cmd == "chat" is the default), check if the
# user passed a prompt, -p, or piped stdin -- if so run once instead of REPL.
# ---------------------------------------------------------------------------
prompt_str <- paste(`prompt...`, collapse = " ")
stdin_piped <- !isatty(stdin())

if (cmd == "chat" &&
    !length(intersect(commandArgs(TRUE),
                      c("chat","repl","app","run","sessions","skills","mcp","info")))) {
  if (nzchar(prompt_str) || isTRUE(print_mode) || stdin_piped) {
    ca_run_once(prompt_str, .mode, model, continue, resume, stream,
                output_fmt = output_format,
                sp = system_prompt, asp = append_system_prompt)
  }
}
