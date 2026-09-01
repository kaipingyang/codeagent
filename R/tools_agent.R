#' @title Agent Sub-agent Tool
#' @description Sub-agent delegation tools. Uses btw's hierarchical subagent
#'   system when available (`btw_tool_agent_subagent`); falls back to codeagent's
#'   own simple sub-agent loop.
#'
#'   Also discovers and registers custom agent definitions from:
#'   - `.btw/agents/*.md` or legacy `.btw/agent-*.md` (project)
#'   - `~/.btw/agents/*.md` or legacy `~/.btw/agent-*.md` (user)
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

# Gate a sub-agent response before any hook, callback, persistence, or parent
# result can observe it. Internal and deliberately returns only a safe scalar.
.subagent_safe_response <- function(response, data_shield = NULL, chat = NULL) {
  if (!is.character(response) || length(response) != 1L)
    response <- "[Sub-agent completed with no text output]"
  if (!inherits(data_shield, "DataShield")) return(response)
  gated <- .output_gate_guarded(
    response, list(data_shield_engine = data_shield), chat)
  gated$text %||% "[data_shield] sub-agent reply withheld (fail-closed)."
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
#' @param async Logical. If `TRUE` and the parent turn is async (concurrent
#'   streaming), run sub-agents via codeagent's promise-based loop so multiple
#'   `Agent` calls in one turn execute concurrently; falls back to synchronous
#'   sub-agents otherwise. Default `FALSE`.
#' @param data_shield Optional [DataShield] inherited from the parent. When set,
#'   the sub-agent's own tools are wrapped before its first LLM request.
#' @param parent_chat Optional parent `ellmer::Chat`. The owned Agent path clones
#'   this Chat, clears history/tools, and verifies provider + Model inheritance.
#' @return An `ellmer::tool()` object.
#' @export
agent_tool <- function(model              = "claude-sonnet-4-6",
                        mode               = "default",
                        rules              = list(),
                        max_turns          = 30L,
                        worktree_isolation = FALSE,
                        hooks              = NULL,
                        ask_fn             = NULL,
                        async              = FALSE,
                        data_shield        = NULL,
                        parent_chat        = NULL) {
  # Prefer btw's upstream subagent (`btw_tool_agent_subagent`: own conversation
  # thread, resumable via session_id) -- no reinvention. Only fall through to
  # codeagent's own sub-agent loop when a codeagent-specific capability is
  # requested that btw's subagent does NOT provide: git-worktree isolation.
  # (Previously btw's tool was returned unconditionally, so worktree_isolation
  # was silently ignored whenever btw was installed -- a latent bug.)
  # Prefer btw's upstream subagent unless a codeagent-specific capability is
  # requested: git-worktree isolation, OR async (concurrent) sub-agents -- btw's
  # tool is synchronous, so async mode uses codeagent's own promise-based loop.
  if (!isTRUE(worktree_isolation) && !isTRUE(async) &&
      is.null(data_shield) && requireNamespace("btw", quietly = TRUE)) {
    tools <- tryCatch(btw::btw_tools("btw_tool_agent_subagent"),
                      error = function(e) list())
    if (length(tools) > 0L) return(tools[[1L]])
  }

  # codeagent's own sub-agent -- used when btw is unavailable OR when
  # worktree_isolation = TRUE (adds isolated git worktree + sidechain
  # persistence + bubble permission mode on top of a plain sub-loop).
  resolved_model <- tryCatch(
    if (inherits(parent_chat, "Chat")) parent_chat$get_model_object()@name else model,
    error = function(e) model)
  ellmer::tool(
    fun = function(description, prompt, subagent_type = NULL) {
      if (!is.null(hooks)) tryCatch(
        hooks$run_subagent_start(description, list(model = resolved_model)),
        error = function(e) NULL)

      # Async sub-agents (concurrent via ellmer tool_mode="concurrent") are only
      # valid when the parent turn runs async; sync chat$chat() rejects
      # promise-returning tools. Gate on the opt-in flag AND an active async turn.
      use_async <- isTRUE(async) && .in_async_turn()

      # --- synchronous setup (shared by both paths) ---
      # Sub-agents run in "bubble" mode: permission decisions bubble up to the
      # parent's ask_fn (mirrors Claude Code's default sub-agent behaviour).
      setup <- tryCatch({
        # Capture repo dir BEFORE the sub-agent may change cwd.
        repo_dir <- getwd()
        wt_path  <- if (isTRUE(worktree_isolation)) .create_worktree(repo_dir) else NULL
        sub_cwd  <- wt_path %||% repo_dir
        sub_mode <- "bubble"
        system_prompt <- .prompt_subagent(description, sub_mode, wt_path)
        sub_settings <- list(
          model = resolved_model, permission_mode = sub_mode,
          cwd = sub_cwd, max_turns = as.integer(max_turns),
          base_url = Sys.getenv("CODEAGENT_BASE_URL", "")
        )
        if (inherits(parent_chat, "Chat")) {
          sub_chat <- parent_chat$clone()
          expected_provider <- parent_chat$get_provider()
          expected_model <- parent_chat$get_model_object()
          sub_chat$set_turns(list())
          sub_chat$set_tools(list())
          if (!.provider_configuration_equal(expected_provider,
                                              sub_chat$get_provider()) ||
              !.model_configuration_equal(expected_model,
                                           sub_chat$get_model_object(),
                                           include_name = TRUE) ||
              length(sub_chat$get_turns()) != 0L ||
              length(sub_chat$get_tools()) != 0L)
            stop("parent Chat clone isolation verification failed")
        } else {
          sub_chat <- .make_chat(sub_settings, sub_cwd)
        }
        # Replace the inherited/default prompt only after clone isolation.
        sub_chat$set_system_prompt(system_prompt)
        # Build tools ungated and install the same single central permission
        # gate used by the parent. Any failure aborts before the first request.
        register_builtin_tools(sub_chat, mode = "bypass", rules = rules,
                               ask_fn = NULL)
        mode_env <- new.env(parent = emptyenv())
        mode_env$mode <- sub_mode
        .install_permission_gate(sub_chat, sub_settings, mode_env, rules,
                                 ask_fn = ask_fn, hooks = hooks)
        if (inherits(data_shield, "DataShield")) data_shield$install(sub_chat)
        list(sub_chat = sub_chat, wt_path = wt_path, repo_dir = repo_dir)
      }, error = function(e)
        structure(paste0("[Error] Agent tool failed: ", conditionMessage(e)),
                  class = "agent_setup_error"))

      if (inherits(setup, "agent_setup_error")) {
        msg <- .subagent_safe_response(unclass(setup), data_shield, NULL)
        if (!is.null(hooks)) tryCatch(
          hooks$run_subagent_stop(description, msg, list(model = resolved_model)),
          error = function(e) NULL)
        return(msg)
      }

      # Cleanup worktree + truncate + fire stop hook. Runs at the correct time
      # in BOTH paths: inline for sync, inside then() for async (so the worktree
      # is not removed before the sub-agent finishes). Replaces the former
      # on.exit(), which would fire too early on the async path.
      finish <- function(r) {
        tryCatch(.cleanup_worktree(setup$wt_path, setup$repo_dir),
                 error = function(e) NULL)
        # Gate before hooks/callbacks/parent output. The runner also gates
        # before persistence; this boundary keeps custom runners safe.
        out <- .subagent_safe_response(
          truncate_tool_result(r, "default"), data_shield, setup$sub_chat)
        if (!is.null(hooks)) tryCatch(
          hooks$run_subagent_stop(description, out, list(model = resolved_model)),
          error = function(e) NULL)
        out
      }

      if (isTRUE(use_async)) {
        # Return a promise -> ellmer runs multiple Agent calls concurrently.
        return(promises::then(
          .run_subagent_loop_async(setup$sub_chat, prompt, max_turns,
                                   persist = TRUE, cwd = setup$repo_dir,
                                   description = description,
                                   data_shield = data_shield),
          finish))
      }

      # Synchronous path (default; safe under chat$chat()).
      r <- tryCatch(
        .run_subagent_loop(setup$sub_chat, prompt, max_turns,
                           persist = TRUE, cwd = setup$repo_dir,
                           description = description,
                           data_shield = data_shield),
        error = function(e) paste0("[Error in sub-agent] ", conditionMessage(e)))
      finish(r)
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
#' @param async Logical. Passed to [agent_tool()]; enables concurrent sub-agents
#'   on async parent turns. Default `FALSE`.
#' @param data_shield Optional [DataShield] inherited by codeagent sub-agents;
#'   disables uninstrumented btw/custom-agent delegation.
#' @param cwd Character. Working directory used for upstream agent discovery.
#' @param parent_chat Optional parent `ellmer::Chat`; reserved for owned
#'   sub-agent lifecycle integration.
#' @param hooks Optional [HookRegistry] used for SubagentStart/Stop lifecycle
#'   events on the owned codeagent Agent path.
#' @return Invisibly returns `chat`.
#' @export
register_agent_tool <- function(chat, model = "claude-sonnet-4-6",
                                  mode = "default", rules = list(),
                                  max_turns = 30L,
                                  worktree_isolation = FALSE,
                                  ask_fn = NULL, async = FALSE,
                                  data_shield = NULL,
                                  cwd = getwd(), parent_chat = NULL,
                                  hooks = NULL) {
  plain_upstream <- is.null(data_shield) && !isTRUE(async) &&
                    !isTRUE(worktree_isolation) &&
                    requireNamespace("btw", quietly = TRUE)
  if (isTRUE(plain_upstream)) {
    build_tools <- function()
      withr::with_dir(cwd, btw::btw_tools("agent"))
    tools <- tryCatch(
      if (inherits(parent_chat, "Chat"))
        withr::with_options(list(btw.client = parent_chat), build_tools())
      else
        build_tools(),
      error = function(e) list())
    if (length(tools)) {
      for (tool in tools) chat$register_tool(tool)
      return(invisible(chat))
    }
  }

  # Shield, async, and worktree modes have codeagent-specific invariants. Never
  # register raw btw/custom delegators alongside this owned Agent path.
  chat$register_tool(agent_tool(model, mode, rules, max_turns,
                                worktree_isolation, hooks = hooks,
                                ask_fn = ask_fn, async = async,
                                data_shield = data_shield,
                                parent_chat = parent_chat))
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
#' Exposes codeagent's tool set as an MCP server via
#' `mcptools::mcp_server()`. Session tools are disabled by default because they
#' expose a separate R-session control surface that does not pass through
#' codeagent's Chat permission gate or Data Shield.
#'
#' @param tools Character vector of btw tool groups to expose, or a list of
#'   `ellmer::tool()` objects. Defaults to all btw tools.
#' @param transport Character. `"stdio"` (default) or `"http"`.
#' @param host Character. Host to bind when `transport = "http"`.
#' @param port Integer. Port to bind when `transport = "http"`.
#' @param session_tools Logical. Expose mcptools R-session controls. Defaults to
#'   `FALSE`; may only be enabled for stdio or a loopback HTTP listener.
#' @param ... Additional arguments passed to the underlying server function.
#' @return Does not return (blocking).
#' @examples
#' \dontrun{
#' # Session controls are disabled unless explicitly requested.
#' codeagent_mcp_server(session_tools = FALSE)
#' }
#' @export
codeagent_mcp_server <- function(tools = NULL,
                                 transport = c("stdio", "http"),
                                 host = "127.0.0.1", port = 8000L,
                                 session_tools = FALSE, ...) {
  transport <- match.arg(transport)
  .mcptools_assert_server()

  if (identical(transport, "http") && isTRUE(session_tools) &&
      !.mcp_loopback_host(host))
    stop("MCP session tools may only be exposed on a loopback HTTP host.",
         call. = FALSE)

  if (is.null(tools)) {
    if (!requireNamespace("btw", quietly = TRUE))
      stop("btw is required when `tools` is NULL.", call. = FALSE)
    tools <- btw::btw_tools()
  }

  args <- list(tools = tools, type = transport,
               session_tools = isTRUE(session_tools))
  if (identical(transport, "http"))
    args <- c(args, list(host = host, port = port))
  do.call(mcptools::mcp_server, c(args, list(...)))
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
#' @param data_shield Optional [DataShield]. Replies are gated before hooks,
#'   return, or persistence. Shielded sidechains are not persisted.
#' @return Character. The sub-agent's text response.
#' @keywords internal
.run_subagent_loop <- function(sub_chat, prompt, max_turns = 30L,
                                persist = FALSE, cwd = getwd(),
                                description = NULL, data_shield = NULL) {
  response <- tryCatch(
    sub_chat$chat(prompt),
    error = function(e) paste0("[Error in sub-agent] ", conditionMessage(e))
  )
  response <- .subagent_safe_response(response, data_shield, sub_chat)
  if (isTRUE(persist) && !inherits(data_shield, "DataShield")) {
    sid <- paste0("subagent-", substr(tryCatch(.generate_uuid_v4(),
                  error = function(e) "x"), 1L, 8L))
    tryCatch(save_session(sub_chat, cwd, sid,
                          title = description %||% "sub-agent"),
             error = function(e) NULL)
  }
  if (is.character(response)) return(response)
  "[Sub-agent completed with no text output]"
}

# ---------------------------------------------------------------------------
# Background (non-blocking) sub-agent tool. Registry/spawn/poll: R/async_agent.R.
# ---------------------------------------------------------------------------

# Model-triggered fire-and-forget delegation. Returns immediately; the result is
# surfaced on a later turn via the system reminder (.bg_reminder_block).
# @keywords internal
background_agent_tool <- function(data_shield = NULL) {
  ellmer::tool(
    fun = function(prompt) {
      if (inherits(data_shield, "DataShield"))
        return(paste0(
          "[data_shield] BackgroundAgent is disabled while Data Shield is active: ",
          "a mirai worker cannot safely inherit the session's protected-data index. ",
          "Use the foreground Agent tool instead."))
      id <- .bg_spawn(prompt)
      if (inherits(id, "bg_error")) return(unclass(id))
      paste0("Started background sub-agent #", id,
             ". It runs concurrently without blocking; its result will be ",
             "delivered to you on a later turn. Continue other work now -- do ",
             "not wait for it, and do not re-spawn the same task.")
    },
    name = "BackgroundAgent",
    description = paste0(
      "Delegate a long-running, independent task to a background sub-agent that ",
      "runs WITHOUT blocking the conversation. Returns immediately with a task ",
      "id; the sub-agent's result is surfaced automatically on a later turn. Use ",
      "for work whose answer you do not need right now (e.g. a broad exploration ",
      "or a slow check) while you continue helping the user."),
    arguments = list(prompt = ellmer::type_string(
      "The full, self-contained task prompt for the background sub-agent.",
      required = TRUE)),
    annotations = ellmer::tool_annotations(title = "Background Agent",
                                           read_only_hint = TRUE))
}

# Register the BackgroundAgent tool (no-op if mirai is unavailable).
# @keywords internal
register_background_agent_tool <- function(chat, data_shield = NULL) {
  if (inherits(data_shield, "DataShield") || .bg_available())
    chat$register_tool(background_agent_tool(data_shield))
  invisible(chat)
}
