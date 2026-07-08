# codeagent 0.1.0

First public release. `codeagent` is an R-native reimplementation of a
command-line coding agent, built on `ellmer` and `btw`. It provides the agent
harness (loop, tools, permissions, compaction, hooks, skills) plus a CLI REPL
and a `shiny` user interface.

## Multi-agent teams (post-0.1.0 additions)

* **Task DAG.** `team_coordinate()` gains `blocked_by` — task dependencies given
  by 1-based index. A task is only claimed once all its blockers are `done`, so
  workers respect ordering while still parallelising independent tasks. Cyclic
  graphs are rejected up front. The shared board's claim is now dependency-aware
  and atomic (`BEGIN IMMEDIATE`).
* **Worktree isolation + crash recovery.** `worktree = TRUE` runs each worker in
  its own git worktree; `board_reclaim_stale()` (wired into the worker loop)
  resets a crashed worker's timed-out task back to pending so its dependents are
  never blocked forever.
* **Event-driven board.** `board_watch()` (built on the `watcher` package) reacts
  to board changes without polling, powering an event-driven coordinator / live
  board view (falls back to polling when watcher is unavailable).
* **LLM-lead coordinator.** `team_lead(goal, max_rounds =)` faithfully ports
  Claude Code's COORDINATOR_MODE: a lead model decomposes the goal into a task
  DAG, the work-stealing team runs it, then the lead reviews results and either
  finishes or adds a follow-up round (bounded loop; decompose/review/coordinate
  steps are injectable for testing).
* **Live dashboard.** `team_dashboard(db_path)` is a standalone Shiny app that
  monitors a running team's board in real time — task table (coloured by
  status), a progress bar, and the inter-agent message log.

## Shiny app UX (post-0.1.0 additions)

* **Instant startup.** The UI shell now renders immediately; the slower tool +
  skill registration runs in the background behind a prominent "Initializing
  codeagent…" overlay, with the chat input gated until it completes. Pass a bare
  `ellmer::Chat` to `codeagent_app()` for this lazy path.

* **Skill metadata disk cache.** `list_skills_meta()` now caches parsed skill
  metadata on disk (`<config>/cache/skills/`, keyed by cwd + a `SKILL.md`
  mtime/count signature), so the slash typeahead and skill tool are near-instant
  on every launch after the first (a disk hit skips the ~20s directory scan). The
  cache self-invalidates when any `SKILL.md` changes or a skill is added/removed.

* **Single-file viewer.** Clicking a file in the Files tree now opens it in one
  static, scrollable "File" tab (code / Markdown / image / CSV) with a filename
  header and close button, replacing the old per-file tabs that could overflow
  and cover the tab strip.

## Security & testing improvements (post-0.1.0 additions)

* **keyring integration** (`R/keyring.R`): Optional API key storage via the OS
  credential store (`keyring` package). `setup.R` offers the keyring as an
  alternative to `~/.Renviron` when the backend is available. Includes
  `.keyring_available()` (session-cached probe), `.keyring_store_key()` with
  graceful fallback to `~/.Renviron`, and `.keyring_get_key()`.
  On headless/server environments the keyring backend probe returns `FALSE` and
  all functions degrade silently to the existing `~/.Renviron` path.

* **webfakes agent integration tests** (`tests/testthat/test-webfakes-agent.R`):
  12 tests that mock the LLM API endpoint with `webfakes`, exercising the full
  agent loop — tool dispatch (Read, Write, Bash), permission gate (bypass vs
  plan), error recovery (HTTP 500), and skill invocation — without hitting a
  real LLM.

* **Explicit tool names**: `bash_tool()`, `read_tool()`, `write_tool()`,
  `edit_tool()`, `multi_edit_tool()`, `glob_tool()`, `grep_tool()`, `ls_tool()`
  now pass `name=` to `ellmer::tool()` so the model can refer to tools by their
  canonical names (Bash, Read, Write, Edit, MultiEdit, Glob, Grep, LS).

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
