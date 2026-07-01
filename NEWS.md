# codeagent 0.1.0

First public release. `codeagent` is an R-native reimplementation of a
command-line coding agent, built on `ellmer` and `btw`. It provides the agent
harness (loop, tools, permissions, compaction, hooks, skills) plus a CLI REPL
and a `shiny` user interface.

## Agent harness

* Agentic loop (`agent_loop()`) with max-turns, token budget, verification, and
  error recovery (prompt-too-long, rate-limit, network, and auth handling).
* Seven-mode permission system: `default`, `plan`, `accept_edits`, `bypass`,
  `dont_ask`, `auto`, and `bubble` (sub-agent decisions bubble to the parent).
  Fine-grained rules match on tool arguments (e.g. `Bash(npm run test *)`).
* Twelve-event hook system covering tool, permission, message, and lifecycle
  events, configurable declaratively from `settings.json`.
* Five-level context compaction (snip, session memory, full summary, prompt
  fallback, context collapse).
* System prompt with tone, task, convention, tool-use, and R-specific guidance.

## Tools

* Core tools: `Bash`, `Read`, `Write`, `Edit`, `MultiEdit`, `Glob`, `Grep`, `LS`.
* `RunR` executes R code behind the permission gate; with sandboxing enabled it
  runs in an isolated `callr` subprocess with a scrubbed environment (secrets
  hidden), no `.Renviron` reload, and a wall-clock timeout.
* `btw` tool groups (docs, git, pkg, env, etc.), web fetch and search, notebook
  tools, task and persistent-todo tools.
* Optional codebase retrieval via `ragnar` (vector + keyword search).

## Coordination

* Sub-agents via `agent_tool()`, with optional git-worktree isolation and
  persistent "sidechain" sessions.
* Parallel teams: `team_run()` (fixed fan-out) and `team_coordinate()`
  (work-stealing over a shared SQLite board with inter-agent messaging), both
  capped to the container's CPU quota via `parallelly`.
* Plan-mode tools let the model enter and exit read-only planning mid-turn.

## State and configuration

* Sessions saved as JSONL with lossless tool-call preservation; fork, rename,
  tag, resume, and rewind (`truncate_chat_turns()` / `/rewind`).
* Auto-memory persisted across sessions, with relevance selection by a small
  fast model.
* `settings.json` configuration mirroring command-line agents: `env` block,
  model tiers, permissions, hooks, MCP servers, sandbox, effort level, and more.
* Model switching mid-conversation (`switch_model()`), lossless where possible.

## Interfaces

* CLI: `codeagent` executable with `run`, `chat`/`repl`, `app`, `skills`, `mcp`,
  and `info` sub-commands; the REPL streams output, shows tool activity, and
  renders reasoning blocks.
* `shiny` app (`codeagent_app()`) with tool cards, session management, and
  theme options.
* MCP server (`codeagent_mcp_server()`, stdio and HTTP) and MCP client
  (`register_mcp_client()`, stdio) for external tool interoperability.
