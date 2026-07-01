#!/usr/bin/env Rapp
#| name: codeagent
#| description: >
#|   R-native coding agent built on ellmer. Run one-shot queries, launch
#|   the Shiny app, manage skills, and start an MCP server.
#| launcher:
#|   default-packages: [base, datasets, utils, stats, methods, codeagent]
#|   vanilla: true

# Global options ----------------------------------------------------------

#| description: Print codeagent version and exit.
version <- FALSE

if (version) {
  cat(format(utils::packageVersion("codeagent")), "\n")
  quit(status = 0)
}

# Helpers -----------------------------------------------------------------

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

# Build client from env vars (CODEAGENT_BASE_URL / CODEAGENT_API_KEY)
ca_make_client <- function(permission_mode = "bypass",
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
    codeagent::codeagent_repl(client, stream = !isTRUE(no_stream),
                              session_id = sid)
  }, error = ca_error)
}

# Subcommand dispatch -----------------------------------------------------

switch(
  cmd <- "",

  # run -- one-shot query -----------------------------------------------
  run = {
    #| description: The prompt to send to the agent.
    `prompt...` <- c()

    #| description: Permission mode.
    #| short: 'm'
    mode <- "bypass"

    #| description: Model override / alias (e.g. anthropic/claude-haiku-4-5).
    model <- ""

    #| description: Continue the most recent session (preserve history).
    #| short: 'c'
    continue <- FALSE

    #| description: Resume a specific session by id (preserve history).
    resume <- ""

    #| description: Stream the response token-by-token to stdout.
    #| short: 's'
    stream <- FALSE

    prompt_str <- paste(`prompt...`, collapse = " ")
    if (!nzchar(prompt_str)) {
      cat("Usage: codeagent run <prompt> [--model spec] [--continue|--resume id] [--stream]\n",
          file = stderr())
      quit(status = 1)
    }

    tryCatch({
      client <- ca_make_client(permission_mode = mode)

      # Lossless model switch (real provider swap, not just a settings field).
      if (nzchar(model))
        client <- codeagent::switch_model(client, model)

      # Restore prior history for --continue / --resume.
      if (isTRUE(continue) || nzchar(resume)) {
        sid <- if (nzchar(resume)) resume else NULL
        restored <- codeagent::restore_session_into_chat(
          client$chat, session_id = sid, cwd = getwd())
        if (is.null(restored))
          cat("[info] no prior session to continue; starting fresh.\n", file = stderr())
      }

      if (isTRUE(stream)) {
        # Token streaming to stdout.
        s <- client$chat$stream(prompt_str)
        for (chunk in s) cat(chunk)
        cat("\n")
      } else {
        resp <- codeagent(client, prompt_str)
        ca_output(resp)
      }
    }, error = ca_error)
  },

  # chat -- interactive REPL (friendly alias for `repl`) ----------------
  chat = {
    #| description: 'Permission mode (default bypass).'
    #| short: 'm'
    mode <- "bypass"

    #| description: Model override / alias.
    model <- ""

    #| description: Continue the most recent session (preserve history).
    #| short: 'c'
    continue <- FALSE

    #| description: 'Stream tokens as they arrive (default: spinner + full response).'
    #| short: 's'
    stream <- FALSE

    ca_start_repl(mode, model, continue, no_stream = !isTRUE(stream))
  },

  # repl -- interactive REPL --------------------------------------------
  repl = {
    #| description: 'Permission mode (default bypass).'
    #| short: 'm'
    mode <- "bypass"

    #| description: Model override / alias.
    model <- ""

    #| description: Continue the most recent session (preserve history).
    #| short: 'c'
    continue <- FALSE

    #| description: 'Stream tokens as they arrive (default: spinner + full response).'
    #| short: 's'
    stream <- FALSE

    ca_start_repl(mode, model, continue, no_stream = !isTRUE(stream))
  },

  # app -- launch Shiny UI -----------------------------------------------
  app = {
    #| description: 'Permission mode (default bypass).'
    #| short: 'm'
    mode <- "bypass"

    #| description: 'UI theme - light, glassmorphism, or dark.'
    #| short: 't'
    theme <- "light"

    #| description: Port number (0 = random).
    port <- 0L

    #| description: Skills to pin at top of sidebar (comma-separated).
    pinned <- ""

    tryCatch({
      client    <- ca_make_client(permission_mode = mode)
      pinned_v  <- if (nzchar(pinned)) trimws(strsplit(pinned, ",")[[1L]]) else character(0)
      port_val  <- if (port == 0L) NULL else port
      codeagent_app(client, pinned_skills = pinned_v, theme = theme,
                    port = port_val)
    }, error = ca_error)
  },

  # skills -- skill management -------------------------------------------
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
            for (m in metas) {
              cat(sprintf("  /%s -- %s\n", m$name, m$description %||% ""))
            }
          }
        }, error = ca_error)
      },

      # skills install ----
      install = {
        #| description: R package to install skill from.
        package <- NULL

        #| description: Specific skill name (optional).
        #| short: 'n'
        name <- ""

        #| description: 'Scope - project or user.'
        #| short: 's'
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

  # mcp -- start MCP server ----------------------------------------------
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

  # info -- show current configuration -----------------------------------
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

if (cmd == "") ca_self_help()
