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
  # gert (libgit2) has no worktree API, so `git worktree add` below still needs
  # the git binary. gert is used only for the repo-membership check.
  if (!nzchar(Sys.which("git"))) return(NULL)
  # Check we're inside a git repo (prefer gert; fall back to a no-shell rev-parse).
  in_repo <- if (requireNamespace("gert", quietly = TRUE)) {
    !is.null(tryCatch(gert::git_find(base_dir), error = function(e) NULL))
  } else {
    repo_check <- system2("git", c("-C", base_dir, "rev-parse", "--git-dir"),
                          stdout = TRUE, stderr = FALSE)
    length(repo_check) > 0L && !grepl("fatal", repo_check[1])
  }
  if (!in_repo) return(NULL)

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
#' @param base_dir Character. The repo the worktree belongs to (so `git
#'   worktree remove` has repo context even if cwd has changed). Defaults to
#'   the current directory.
#' @keywords internal
.cleanup_worktree <- function(wt_path, base_dir = getwd()) {
  if (is.null(wt_path)) return(invisible(NULL))
  tryCatch({
    # Run with explicit repo context (-C base_dir) so removal works regardless
    # of the caller's current working directory.
    system2("git", c("-C", base_dir, "worktree", "remove", "--force", wt_path),
            stdout = FALSE, stderr = FALSE)
    # Prune any dangling worktree admin entries.
    system2("git", c("-C", base_dir, "worktree", "prune"),
            stdout = FALSE, stderr = FALSE)
    # Belt-and-braces: remove the directory if git left it behind.
    if (dir.exists(wt_path)) unlink(wt_path, recursive = TRUE, force = TRUE)
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
#' @param ask_fn Function or NULL. Parent permission callback. Sub-agents run in
#'   "bubble" mode, so any "ask" decision is forwarded to this function.
#' @return An `ellmer::tool()` object.
#' @export
agent_tool <- function(model              = "claude-sonnet-4-6",
                        mode               = "default",
                        rules              = list(),
                        max_turns          = 30L,
                        worktree_isolation = FALSE,
                        hooks              = NULL,
                        ask_fn             = NULL) {
  # Prefer btw's upstream subagent (`btw_tool_agent_subagent`: own conversation
  # thread, resumable via session_id) -- no reinvention. Only fall through to
  # codeagent's own sub-agent loop when a codeagent-specific capability is
  # requested that btw's subagent does NOT provide: git-worktree isolation.
  # (Previously btw's tool was returned unconditionally, so worktree_isolation
  # was silently ignored whenever btw was installed -- a latent bug.)
  if (!isTRUE(worktree_isolation) && requireNamespace("btw", quietly = TRUE)) {
    tools <- tryCatch(btw::btw_tools("btw_tool_agent_subagent"),
                      error = function(e) list())
    if (length(tools) > 0L) return(tools[[1L]])
  }

  # codeagent's own sub-agent -- used when btw is unavailable OR when
  # worktree_isolation = TRUE (adds isolated git worktree + sidechain
  # persistence + bubble permission mode on top of a plain sub-loop).
  ellmer::tool(
    fun = function(description, prompt, subagent_type = NULL) {
      if (!is.null(hooks)) tryCatch(
        hooks$run_subagent_start(description, list(model = model)),
        error = function(e) NULL)
      result <- tryCatch({
        # Optionally create an isolated worktree. Capture the repo dir BEFORE
        # the sub-agent may change cwd, so cleanup always has repo context.
        repo_dir <- getwd()
        wt_path <- if (isTRUE(worktree_isolation)) .create_worktree(repo_dir) else NULL
        sub_cwd <- wt_path %||% repo_dir
        on.exit(.cleanup_worktree(wt_path, repo_dir), add = TRUE)

        # Sub-agents run in "bubble" mode: permission decisions bubble up to
        # the parent's ask_fn rather than being resolved locally (mirrors
        # Claude Code's default sub-agent behaviour). The parent ask_fn is
        # passed through so a bubbled "ask" is answered by the parent.
        sub_mode <- "bubble"
        system_prompt <- .prompt_subagent(description, sub_mode, wt_path)
        sub_settings <- list(
          model = model, permission_mode = sub_mode,
          cwd = sub_cwd, max_turns = as.integer(max_turns),
          base_url = Sys.getenv("CODEAGENT_BASE_URL", "")
        )
        sub_chat <- .make_chat(sub_settings, sub_cwd, system_prompt = system_prompt)
        register_builtin_tools(sub_chat, mode = sub_mode, rules = rules,
                               ask_fn = ask_fn)
        # Persist the sub-agent's conversation as a sidechain session so its
        # history is not ephemeral (stored under the parent project dir).
        r <- .run_subagent_loop(sub_chat, prompt, max_turns,
                                persist = TRUE, cwd = repo_dir,
                                description = description)
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
    name = "Agent",
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
#' @param ask_fn Function or NULL. Parent permission callback forwarded to the
#'   sub-agent (which runs in "bubble" mode).
#' @return Invisibly returns `chat`.
#' @export
register_agent_tool <- function(chat, model = "claude-sonnet-4-6",
                                  mode = "default", rules = list(),
                                  max_turns = 30L,
                                  worktree_isolation = FALSE,
                                  ask_fn = NULL) {
  chat$register_tool(agent_tool(model, mode, rules, max_turns,
                                worktree_isolation, ask_fn = ask_fn))

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
#' Exposes codeagent's tool set as an MCP server. By default uses btw's
#' `btw_mcp_server()` over stdio (for Claude Desktop / VS Code MCP config). With
#' `transport = "http"` it serves over HTTP via `mcptools::mcp_server()` (>= 0.2.1),
#' enabling remote MCP clients. The server runs in a blocking loop.
#'
#' @param tools Character vector of btw tool groups to expose, or a list of
#'   `ellmer::tool()` objects. Defaults to all btw tools.
#' @param transport Character. `"stdio"` (default) or `"http"`.
#' @param host Character. Host to bind when `transport = "http"`.
#' @param port Integer. Port to bind when `transport = "http"`.
#' @param ... Additional arguments passed to the underlying server function.
#' @return Does not return (blocking).
#' @export
codeagent_mcp_server <- function(tools = NULL,
                                 transport = c("stdio", "http"),
                                 host = "127.0.0.1", port = 8000L, ...) {
  transport <- match.arg(transport)

  if (identical(transport, "http")) {
    if (!requireNamespace("mcptools", quietly = TRUE) ||
        utils::packageVersion("mcptools") < "0.2.1")
      stop("HTTP MCP server requires mcptools (>= 0.2.1). ",
           "Install with: install.packages('mcptools')", call. = FALSE)
    if (is.null(tools) && requireNamespace("btw", quietly = TRUE))
      tools <- btw::btw_tools()
    return(mcptools::mcp_server(tools = tools, type = "http",
                                host = host, port = port, ...))
  }

  # Default: stdio via btw
  if (!requireNamespace("btw", quietly = TRUE))
    stop("btw package required for stdio MCP server. Install with: install.packages('btw')",
         call. = FALSE)
  if (is.null(tools)) tools <- btw::btw_tools()
  btw::btw_mcp_server(tools = tools, ...)
}

# ---------------------------------------------------------------------------
# Internal: simple sub-agent loop (btw fallback)
# ---------------------------------------------------------------------------

#' Run a sub-agent's conversation loop, optionally persisting its session
#'
#' When `persist = TRUE` the sub-agent's full conversation is saved to a
#' "sidechain" JSONL under the project's session directory (id prefixed with
#' `subagent-`), so sub-agent history survives instead of being ephemeral.
#'
#' @param sub_chat An `ellmer::Chat` for the sub-agent.
#' @param prompt Character. The task prompt.
#' @param max_turns Integer. Max turns (currently single-shot chat).
#' @param persist Logical. Save the sub-agent session to disk.
#' @param cwd Character. Project dir for session storage.
#' @param description Character. Used as the sidechain session title.
#' @return Character. The sub-agent's text response.
#' @keywords internal
.run_subagent_loop <- function(sub_chat, prompt, max_turns = 30L,
                                persist = FALSE, cwd = getwd(),
                                description = NULL) {
  response <- tryCatch(
    sub_chat$chat(prompt),
    error = function(e) paste0("[Error in sub-agent] ", conditionMessage(e))
  )
  if (isTRUE(persist)) {
    sid <- paste0("subagent-", substr(tryCatch(.generate_uuid_v4(),
                  error = function(e) "x"), 1L, 8L))
    tryCatch(save_session(sub_chat, cwd, sid,
                          title = description %||% "sub-agent"),
             error = function(e) NULL)
  }
  if (is.character(response)) return(response)
  "[Sub-agent completed with no text output]"
}
