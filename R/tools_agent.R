#' @title Agent Sub-agent Tool
#' @description Sub-agent delegation tools. Uses btw's hierarchical subagent
#'   system when available (`btw_tool_agent_subagent`); falls back to codeagent's
#'   own simple sub-agent loop.
#'
#'   Also discovers and registers custom agent definitions from:
#'   - `.btw/agent-*.md` (project)
#'   - `~/.btw/agent-*.md` (user)
#'   - `.claude/agents/` (Claude Code compat)
#' @name tools_agent
#' @keywords internal
NULL

# ---------------------------------------------------------------------------
# Worktree isolation helpers
# ---------------------------------------------------------------------------

#' Create an isolated git worktree for a sub-agent
#'
#' Creates a temporary git worktree so the sub-agent can make changes
#' without affecting the main working tree. The caller is responsible for
#' cleanup via [.cleanup_worktree()].
#'
#' @param base_dir Character. Git repo root (default current dir).
#' @return Character. Path to new worktree, or NULL if git not available.
#' @keywords internal
.create_worktree <- function(base_dir = getwd()) {
  if (!nzchar(Sys.which("git"))) return(NULL)
  # Check we're inside a git repo
  repo_check <- system2("git", c("-C", base_dir, "rev-parse", "--git-dir"),
                         stdout = TRUE, stderr = FALSE)
  if (!length(repo_check) || grepl("fatal", repo_check[1])) return(NULL)

  wt_path <- file.path(tempdir(), paste0("codeagent-wt-", .generate_uuid_v4()))
  branch  <- paste0("codeagent-subagent-", substr(.generate_uuid_v4(), 1L, 8L))

  result <- system2("git",
    c("-C", base_dir, "worktree", "add", "--detach", wt_path),
    stdout = TRUE, stderr = TRUE
  )
  if (!is.null(attr(result, "status")) && attr(result, "status") != 0L) return(NULL)
  wt_path
}

#' Remove a git worktree
#' @param wt_path Character. Path returned by [.create_worktree()].
#' @keywords internal
.cleanup_worktree <- function(wt_path) {
  if (is.null(wt_path) || !dir.exists(wt_path)) return(invisible(NULL))
  tryCatch({
    system2("git", c("worktree", "remove", "--force", wt_path),
            stdout = FALSE, stderr = FALSE)
    if (dir.exists(wt_path)) unlink(wt_path, recursive = TRUE)
  }, error = function(e) NULL)
  invisible(NULL)
}

# ---------------------------------------------------------------------------
# Agent tool (btw subagent or codeagent fallback)
# ---------------------------------------------------------------------------

#' Create the Agent tool
#'
#' When btw is available, delegates to `btw_tool_agent_subagent()` which
#' provides isolated chat sessions with resumable state. Falls back to
#' codeagent's own sub-agent loop otherwise.
#'
#' @param model Character. Model for sub-agents (fallback only).
#' @param mode Character. Permission mode (inherited from parent).
#' @param rules List. Permission rules (inherited).
#' @param max_turns Integer. Max turns for sub-agent fallback (default 30).
#' @param worktree_isolation Logical. Run sub-agent in an isolated git worktree.
#' @param hooks A [HookRegistry] or NULL. Fires SubagentStart/Stop on the
#'   codeagent fallback sub-agent.
#'   Only applies to the fallback implementation; btw subagent handles its
#'   own isolation.
#' @return An `ellmer::tool()` object.
#' @export
agent_tool <- function(model              = "claude-sonnet-4-6",
                        mode               = "default",
                        rules              = list(),
                        max_turns          = 30L,
                        worktree_isolation = FALSE,
                        hooks              = NULL) {
  # Use btw's subagent when available (preferred: isolated session, resumable)
  if (requireNamespace("btw", quietly = TRUE)) {
    tools <- tryCatch(btw::btw_tools("btw_tool_agent_subagent"),
                      error = function(e) list())
    if (length(tools) > 0L) return(tools[[1L]])
  }

  # Fallback: codeagent's own simple sub-agent
  ellmer::tool(
    fun = function(description, prompt, subagent_type = NULL) {
      if (!is.null(hooks)) tryCatch(
        hooks$run_subagent_start(description, list(model = model)),
        error = function(e) NULL)
      result <- tryCatch({
        # Optionally create an isolated worktree
        wt_path <- if (isTRUE(worktree_isolation)) .create_worktree() else NULL
        sub_cwd <- wt_path %||% getwd()
        on.exit(.cleanup_worktree(wt_path), add = TRUE)

        system_prompt <- paste0(
          "You are a sub-agent helping with: ", description, "\n",
          "Complete the task thoroughly and return your findings/results.\n",
          "Running in sub-agent mode (permission: ", mode, ").",
          if (!is.null(wt_path)) paste0("\nWorking directory: ", sub_cwd) else ""
        )
        sub_settings <- list(
          model = model, permission_mode = mode,
          cwd = sub_cwd, max_turns = as.integer(max_turns),
          base_url = Sys.getenv("CODEAGENT_BASE_URL", "")
        )
        sub_chat <- .make_chat(sub_settings, sub_cwd, system_prompt = system_prompt)
        register_builtin_tools(sub_chat, mode = mode, rules = rules)
        r <- .run_subagent_loop(sub_chat, prompt, max_turns)
        truncate_tool_result(r, "default")
      }, error = function(e) {
        paste0("[Error] Agent tool failed: ", conditionMessage(e))
      })
      if (!is.null(hooks)) tryCatch(
        hooks$run_subagent_stop(description, result, list(model = model)),
        error = function(e) NULL)
      result
    },
    description = paste0(
      "Spawn a sub-agent to handle a complex, multi-step delegated task. ",
      "The sub-agent starts fresh with its own context and returns a summary."
    ),
    arguments = list(
      description   = ellmer::type_string(
        "Short description of what the sub-agent will do.", required = TRUE),
      prompt        = ellmer::type_string(
        "The full task prompt for the sub-agent.", required = TRUE),
      subagent_type = ellmer::type_string(
        "Optional hint (e.g. 'explore', 'plan').", required = FALSE)
    ),
    annotations = ellmer::tool_annotations(
      title = "Agent", read_only_hint = FALSE, destructive_hint = FALSE
    )
  )
}

# ---------------------------------------------------------------------------
# Register agent tool + btw custom agents
# ---------------------------------------------------------------------------

#' Register the Agent tool and any btw custom agent tools
#'
#' Registers `btw_tool_agent_subagent` (or fallback), plus any custom agents
#' discovered from `.btw/agent-*.md`, `.claude/agents/`, etc.
#'
#' @param chat An `ellmer::Chat` object.
#' @param model Character. Model for sub-agents (fallback).
#' @param mode Character. Permission mode.
#' @param rules List. Permission rules.
#' @param max_turns Integer. Max turns per sub-agent.
#' @param worktree_isolation Logical. Run sub-agents in isolated git worktrees.
#' @return Invisibly returns `chat`.
#' @export
register_agent_tool <- function(chat, model = "claude-sonnet-4-6",
                                  mode = "default", rules = list(),
                                  max_turns = 30L,
                                  worktree_isolation = FALSE) {
  chat$register_tool(agent_tool(model, mode, rules, max_turns, worktree_isolation))

  # Register custom btw agent tools from discovered .md files
  if (requireNamespace("btw", quietly = TRUE)) {
    tryCatch({
      ns <- getNamespace("btw")
      # btw_agent_tool() discovers agents from .btw/, .claude/agents/, etc.
      # btw_tools() doesn't list them by default -- use btw_agent_tool() per path
      agent_dirs <- c(
        file.path(getwd(), ".btw"),
        file.path(getwd(), ".claude", "agents"),
        file.path(path.expand("~"), ".btw")
      )
      for (d in agent_dirs[dir.exists(agent_dirs)]) {
        agent_files <- list.files(d, pattern = "^agent-.*\\.md$",
                                   full.names = TRUE)
        for (f in agent_files) {
          tryCatch({
            t <- ns$btw_agent_tool(f)
            chat$register_tool(t)
          }, error = function(e) NULL)
        }
      }
    }, error = function(e) NULL)
  }

  invisible(chat)
}

# ---------------------------------------------------------------------------
# MCP server wrapper
# ---------------------------------------------------------------------------

#' Install the codeagent CLI
#'
#' Installs the `codeagent` CLI script (powered by Rapp) to a directory on
#' your PATH. After installation, run `codeagent run "prompt"`,
#' `codeagent app`, `codeagent skills list`, etc.
#'
#' @param destdir Character or NULL. Destination directory. NULL uses
#'   `~/.local/bin` (Linux/macOS) or `~/bin` as fallback.
#' @return Character. Path(s) to installed script(s), invisibly.
#' @export
install_codeagent_cli <- function(destdir = NULL) {
  if (!requireNamespace("Rapp", quietly = TRUE))
    stop("Rapp package required. Install with: ",
         "install.packages('Rapp', repos='https://r-lib.r-universe.dev')",
         call. = FALSE)

  result <- Rapp::install_pkg_cli_apps(package = "codeagent",
                                        destdir = destdir)
  for (path in result)
    cli::cli_alert_success("Installed {.code codeagent} CLI to {.path {path}}")
  invisible(result)
}
#'
#' Exposes codeagent's tool set as an MCP server, powered by btw's
#' `btw_mcp_server()`. The server runs in a blocking loop and is designed
#' for non-interactive use (e.g. Claude Desktop, VS Code MCP config).
#'
#' @param tools Character vector of btw tool groups to expose, or a list of
#'   `ellmer::tool()` objects. Defaults to all btw tools.
#' @param ... Additional arguments passed to `btw::btw_mcp_server()`.
#' @return Does not return (blocking).
#' @export
codeagent_mcp_server <- function(tools = NULL, ...) {
  if (!requireNamespace("btw", quietly = TRUE))
    stop("btw package required for MCP server. Install with: install.packages('btw')",
         call. = FALSE)
  if (is.null(tools)) tools <- btw::btw_tools()
  btw::btw_mcp_server(tools = tools, ...)
}

# ---------------------------------------------------------------------------
# Internal: simple sub-agent loop (btw fallback)
# ---------------------------------------------------------------------------

.run_subagent_loop <- function(sub_chat, prompt, max_turns = 30L) {
  response <- tryCatch(
    sub_chat$chat(prompt),
    error = function(e) paste0("[Error in sub-agent] ", conditionMessage(e))
  )
  if (is.character(response)) return(response)
  "[Sub-agent completed with no text output]"
}
