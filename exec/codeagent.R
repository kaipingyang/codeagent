#!/usr/bin/env Rapp
#| name: codeagent
#| description: >
#|   R-native coding agent built on ellmer. Run interactive sessions, launch
#|   the Shiny app, manage skills, and start an MCP server.
#|
#|   Usage:
#|     codeagent                    # start interactive REPL (default mode)
#|     codeagent -y                 # start interactive REPL (bypass mode)
#|     codeagent "your query"       # one-shot query
#|     codeagent -p "your query"    # one-shot query (non-interactive, print)
#|     codeagent run "your query"   # one-shot query (explicit subcommand)
#|     codeagent app                # launch Shiny UI
#|     codeagent app -y             # launch Shiny UI in bypass mode
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
#|   environments such as Docker containers with no internet access.
#|   Equivalent to --dangerously-skip-permissions in Claude Code.
#| short: 'y'
yolo <- FALSE

#| description: Model override / alias (e.g. anthropic/claude-haiku-4-5).
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
#|   Prompt text for one-shot mode.  When no subcommand is given and a
#|   prompt is provided (or -p is set), codeagent runs a single query and
#|   exits.  With no prompt and no subcommand, codeagent starts the REPL.
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

ca_output <- function(x) {
  if (is.character(x)) cat(paste(x, collapse = "\n"), "\n")
  else cat(format(x), "\n")
}

ca_self_help <- function(...) {
  script_path <- commandArgs(TRUE)[1]
  Rapp:::print_app_help(script_path, yaml = FALSE, command_path = c(...))
  quit(status = 1)
}

# Build client from env vars (CODEAGENT_BASE_URL / CODEAGENT_API_KEY).
# Default permission mode is "default" (interactive approval for write ops).
# Pass yolo=TRUE or use -y/--yolo for bypass mode.
ca_make_client <- function(permission_mode = "default",
                            btw_groups = NULL) {
  tryCatch(
    codeagent_client(
      permission_mode = permission_mode,
      btw_groups      = btw_groups
    ),
    error = function(e) {
      cat("[Error] Could not build codeagent client:", conditionMessage(e), "\n",
          file = stderr())
      quit(status = 1)
    }
  )
}

# Shared REPL launcher for the `chat` and `repl` subcommands.
ca_start_repl <- function(mode, model, continue, no_stream) {
  tryCatch({
    client <- ca_make_client(permission_mode = mode)
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

# One-shot runner used by `run` subcommand and bare-prompt invocation.
ca_run_once <- function(prompt_str, mode, model, continue, resume, stream) {
  if (!nzchar(prompt_str)) {
    cat("Usage: codeagent run <prompt> [--model spec] [-c|--resume id] [-s]\n",
        file = stderr())
    quit(status = 1)
  }
  tryCatch({
    client <- ca_make_client(permission_mode = mode)
    if (nzchar(model))
      client <- codeagent::switch_model(client, model)
    if (isTRUE(continue) || nzchar(resume)) {
      sid <- if (nzchar(resume)) resume else NULL
      restored <- codeagent::restore_session_into_chat(
        client$chat, session_id = sid, cwd = getwd())
      if (is.null(restored))
        cat("[info] no prior session to continue; starting fresh.\n", file = stderr())
    }
    if (isTRUE(stream)) {
      s <- client$chat$stream(prompt_str)
      for (chunk in s) cat(chunk)
      cat("\n")
    } else {
      resp <- codeagent(client, prompt_str)
      ca_output(resp)
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
    ca_run_once(prompt_str, .mode, model, continue, resume, stream)
  },

  # chat -- interactive REPL (default subcommand) ---------------------------
  chat = {
    ca_start_repl(.mode, model, continue, no_stream = !isTRUE(stream))
  },

  # repl -- alias for chat --------------------------------------------------
  repl = {
    ca_start_repl(.mode, model, continue, no_stream = !isTRUE(stream))
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
      pinned_v <- if (nzchar(pinned)) trimws(strsplit(pinned, ",")[[1L]]) else character(0)
      port_val <- if (port == 0L) NULL else port
      codeagent_app(client, pinned_skills = pinned_v, theme = theme,
                    port = port_val)
    }, error = ca_error)
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
# Bare-prompt / print-mode fallback
# When no subcommand was matched (cmd == "chat" is the default), check if the
# user actually passed a prompt or -p without a subcommand -- if so run once.
# ---------------------------------------------------------------------------
prompt_str <- paste(`prompt...`, collapse = " ")
if ((nzchar(prompt_str) || isTRUE(print_mode)) &&
    cmd == "chat" &&
    !length(intersect(commandArgs(TRUE), c("chat","repl","app","run","skills","mcp","info")))) {
  ca_run_once(prompt_str, .mode, model, continue, resume, stream)
}
