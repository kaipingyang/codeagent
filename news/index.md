# Changelog

## codeagent 0.1.0

First public release. `codeagent` is an R-native reimplementation of a
command-line coding agent, built on `ellmer` and `btw`. It provides the
agent harness (loop, tools, permissions, compaction, hooks, skills) plus
a CLI REPL and a `shiny` user interface.

### Model tier env var rename — breaking changes

Three environment variables have been renamed to remove vendor-specific
names. Update your `.Renviron` / `settings.json` env block accordingly:

| Old                              | New                     | Meaning               |
| -------------------------------- | ----------------------- | --------------------- |
| `CODEAGENT_DEFAULT_SONNET_MODEL` | `CODEAGENT_MODEL`       | Everyday main model   |
| `CODEAGENT_DEFAULT_OPUS_MODEL`   | `CODEAGENT_HEAVY_MODEL` | High-capability model |
| `CODEAGENT_SMALL_FAST_MODEL`     | `CODEAGENT_FAST_MODEL`  | Cheap/fast model      |

Tier aliases used in `/model` and `codeagent.md` also changed:
`"sonnet"` → `"main"`, `"opus"` → `"heavy"`, `"haiku"` → `"fast"`.

`CODEAGENT_MODEL` now serves dual purpose: it sets both the default
model and the `"main"` tier alias (previously `CODEAGENT_MODEL` and
`CODEAGENT_DEFAULT_SONNET_MODEL` were separate; they are now merged).

### CLI/ink unified entry point — breaking changes (plan [\#20](https://github.com/kaipingyang/codeagent/issues/20))

  - **Default permission mode is now `"default"`** across all entry
    points (CLI, Shiny, ink). Previously all CLI subcommands defaulted
    to `"bypass"`. Write operations (file edits, shell commands) now
    prompt for approval unless you explicitly opt into bypass mode.

  - **`-y` / `--yolo`** — new global flag for the CLI that enables
    bypass mode (skips all permission prompts). Equivalent to Claude
    Code’s `--dangerously-skip-permissions`. Short-hand: `-y`.
    
        codeagent -y           # bypass REPL
        codeagent app -y       # bypass Shiny app
        codeagent run "q" -y   # bypass one-shot query

  - **`codeagent` without a subcommand** now starts the interactive REPL
    directly (equivalent to `codeagent chat`). Previously a subcommand
    was required.

  - **`-p` / `--print-mode`** — new flag for one-shot non-interactive
    output. `codeagent "query"` or `codeagent -p "query"` runs a single
    query and exits.

  - **`-m` now means `--model`** (breaking). The old `-m`/`--mode` alias
    has been removed. Use `-y`/`--yolo` for bypass mode instead.

  - **`ink_ui()` gains `yolo = FALSE`** parameter. When `TRUE`, sets
    `INK_YOLO=1` so the codeagent backend runs in bypass mode. The
    `inkai` terminal command also accepts `-y`/`--yolo`.
    
        ink_ui("codeagent", yolo = TRUE)   # bypass
        # or from terminal:
        inkai codeagent -y                 # bypass

  - **`INK_YOLO` env var** — set to `"1"` to enable bypass mode in ink
    when launching the `inkai` command directly: `INK_YOLO=1 inkai
    codeagent`.

  - **`codeagent_app(permission_mode = "default")` unchanged** — Shiny
    was already correct; pass `permission_mode = "bypass"` explicitly
    when needed.

  - **`R/cli_dispatch.R`** — new internal helpers `.ca_resolve_mode()`
    and `.ca_dispatch()` expose CLI dispatch logic as testable pure
    functions.

#### Migration guide

| Old                                | New                                           |
| ---------------------------------- | --------------------------------------------- |
| `codeagent chat`                   | `codeagent`                                   |
| `codeagent chat -m bypass`         | `codeagent -y`                                |
| `codeagent -m bypass`              | `codeagent -y`                                |
| `ink_ui("codeagent")` (was bypass) | `ink_ui("codeagent", yolo = TRUE)` for bypass |
| `inkai codeagent` (was bypass)     | `inkai codeagent -y` for bypass               |

### Unified agent streaming API (plan [\#19](https://github.com/kaipingyang/codeagent/issues/19))

  - **`codeagent_stream_async()`** — new exported function. Streams one
    agent turn asynchronously (`coro::async` promise). Runs the full
    turn pipeline (compaction, system-reminder injection, session save,
    cost tracking via `get_cost(include="last")`). Fires typed
    callbacks: `on_delta`, `on_thinking`, `on_tool_request` (pre-gate,
    from stream chunk), `on_tool_result` (with typed `display` contract
    from `.adapt_tool_result()`), `on_error`, `on_usage`. Supports
    `stream_controller` for cancellation and `tool_mode` for concurrent
    tool execution.

  - **`codeagent_stream()`** — synchronous wrapper around
    `codeagent_stream_async()` using `later::run_now()` to pump the
    event loop. Handles Ctrl+C gracefully (cancels the stream via
    `stream_controller`, does not re-throw the interrupt condition).
    Intended for CLI and ink frontends.

  - **Turn pipeline helpers** (`R/turn_pipeline.R`, internal):
    `.turn_setup()` consolidates compaction + resource replacement +
    system-reminder injection into one call. `.turn_teardown()`
    consolidates session save + usage + `cost_last`. Both are now shared
    by console, Shiny, and ink.

  - **Shiny system-reminder injection fixed.** `server_chat.R`’s
    `stream_task` now injects the `<system-reminder>` block
    (date/iteration/cwd/memory) on every turn, matching the behaviour of
    the console REPL and `agent_loop()`.

  - **Console Ctrl+C repair.** `codeagent_console()` now creates a
    `stream_controller` per turn and catches `interrupt` conditions,
    cancelling the stream gracefully. Previously Ctrl+C could corrupt
    the chat state.

  - **Callback deduplication.** `.register_repl_tool_callbacks()` is now
    guarded by `.chat_once()` to prevent stacking display callbacks if
    `codeagent_console()` is called more than once on the same chat
    object.

  - **`.patch_interrupted_chat()` retired.** Removed from all call
    sites. ellmer 0.4.0+
    ([\#840](https://github.com/kaipingyang/codeagent/issues/840)) and
    0.4.1+
    ([\#643](https://github.com/kaipingyang/codeagent/issues/643))
    handle orphaned tool requests and `AssistantPartialTurn`
    automatically.

  - **`inkAssistantUI` tool cards upgraded.** `ink_reply_stream()` now
    calls `codeagent_stream()` when available (full turn pipeline +
    display contract). `on_tool_result` receives a rich `display` field
    (title/kind/payload) instead of a plain string. The `ink_server()`
    initialises per-session `CompactionController` /
    `ContentReplacementState` / `session_id` so turns are properly
    managed.

### Multi-agent teams (post-0.1.0 additions)

  - **Task DAG.** `team_coordinate()` gains `blocked_by` — task
    dependencies given by 1-based index. A task is only claimed once all
    its blockers are `done`, so workers respect ordering while still
    parallelising independent tasks. Cyclic graphs are rejected up
    front. The shared board’s claim is now dependency-aware and atomic
    (`BEGIN IMMEDIATE`).
  - **Worktree isolation + crash recovery.** `worktree = TRUE` runs each
    worker in its own git worktree; `board_reclaim_stale()` (wired into
    the worker loop) resets a crashed worker’s timed-out task back to
    pending so its dependents are never blocked forever.
  - **Event-driven board.** `board_watch()` (built on the `watcher`
    package) reacts to board changes without polling, powering an
    event-driven coordinator / live board view (falls back to polling
    when watcher is unavailable).
  - **LLM-lead coordinator.** `team_lead(goal, max_rounds =)` faithfully
    ports Claude Code’s COORDINATOR\_MODE: a lead model decomposes the
    goal into a task DAG, the work-stealing team runs it, then the lead
    reviews results and either finishes or adds a follow-up round
    (bounded loop; decompose/review/coordinate steps are injectable for
    testing).
  - **Live dashboard.** `team_dashboard(db_path)` is a standalone Shiny
    app that monitors a running team’s board in real time — task table
    (coloured by status), a progress bar, and the inter-agent message
    log.

### Shiny app UX (post-0.1.0 additions)

  - **Instant startup.** The UI shell now renders immediately; the
    slower tool + skill registration runs in the background behind a
    prominent “Initializing codeagent…” overlay, with the chat input
    gated until it completes. Pass a bare `ellmer::Chat` to
    `codeagent_app()` for this lazy path.

  - **Skill metadata disk cache.** `list_skills_meta()` now caches
    parsed skill metadata on disk (`<config>/cache/skills/`, keyed by
    cwd + a `SKILL.md` mtime/count signature), so the slash typeahead
    and skill tool are near-instant on every launch after the first (a
    disk hit skips the \~20s directory scan). The cache self-invalidates
    when any `SKILL.md` changes or a skill is added/removed.

  - **Single-file viewer.** Clicking a file in the Files tree now opens
    it in one static, scrollable “File” tab (code / Markdown / image /
    CSV) with a filename header and close button, replacing the old
    per-file tabs that could overflow and cover the tab strip.

### Security & testing improvements (post-0.1.0 additions)

  - **keyring integration** (`R/keyring.R`): Optional API key storage
    via the OS credential store (`keyring` package). `setup.R` offers
    the keyring as an alternative to `~/.Renviron` when the backend is
    available. Includes `.keyring_available()` (session-cached probe),
    `.keyring_store_key()` with graceful fallback to `~/.Renviron`, and
    `.keyring_get_key()`. On headless/server environments the keyring
    backend probe returns `FALSE` and all functions degrade silently to
    the existing `~/.Renviron` path.

  - **webfakes agent integration tests**
    (`tests/testthat/test-webfakes-agent.R`): 12 tests that mock the LLM
    API endpoint with `webfakes`, exercising the full agent loop — tool
    dispatch (Read, Write, Bash), permission gate (bypass vs plan),
    error recovery (HTTP 500), and skill invocation — without hitting a
    real LLM.

  - **Explicit tool names**: `bash_tool()`, `read_tool()`,
    `write_tool()`, `edit_tool()`, `multi_edit_tool()`, `glob_tool()`,
    `grep_tool()`, `ls_tool()` now pass `name=` to `ellmer::tool()` so
    the model can refer to tools by their canonical names (Bash, Read,
    Write, Edit, MultiEdit, Glob, Grep, LS).

### Agent harness

  - Agentic loop (`agent_loop()`) with max-turns, token budget,
    verification, and error recovery (prompt-too-long, rate-limit,
    network, and auth handling).
  - Seven-mode permission system: `default`, `plan`, `accept_edits`,
    `bypass`, `dont_ask`, `auto`, and `bubble` (sub-agent decisions
    bubble to the parent). Fine-grained rules match on tool arguments
    (e.g. `Bash(npm run test *)`).
  - Twelve-event hook system covering tool, permission, message, and
    lifecycle events, configurable declaratively from `settings.json`.
  - Five-level context compaction (snip, session memory, full summary,
    prompt fallback, context collapse).
  - System prompt with tone, task, convention, tool-use, and R-specific
    guidance.

### Tools

  - Core tools: `Bash`, `Read`, `Write`, `Edit`, `MultiEdit`, `Glob`,
    `Grep`, `LS`.
  - `RunR` executes R code behind the permission gate; with sandboxing
    enabled it runs in an isolated `callr` subprocess with a scrubbed
    environment (secrets hidden), no `.Renviron` reload, and a
    wall-clock timeout.
  - `btw` tool groups (docs, git, pkg, env, etc.), web fetch and search,
    notebook tools, task and persistent-todo tools.
  - Optional codebase retrieval via `ragnar` (vector + keyword search).

### Coordination

  - Sub-agents via `agent_tool()`, with optional git-worktree isolation
    and persistent “sidechain” sessions.
  - Parallel teams: `team_run()` (fixed fan-out) and `team_coordinate()`
    (work-stealing over a shared SQLite board with inter-agent
    messaging), both capped to the container’s CPU quota via
    `parallelly`.
  - Plan-mode tools let the model enter and exit read-only planning
    mid-turn.

### State and configuration

  - Sessions saved as JSONL with lossless tool-call preservation; fork,
    rename, tag, resume, and rewind (`truncate_chat_turns()` /
    `/rewind`).
  - Auto-memory persisted across sessions, with relevance selection by a
    small fast model.
  - `settings.json` configuration mirroring command-line agents: `env`
    block, model tiers, permissions, hooks, MCP servers, sandbox, effort
    level, and more.
  - Model switching mid-conversation (`switch_model()`), lossless where
    possible.

### Interfaces

  - CLI: `codeagent` executable with `run`, `chat`/`repl`, `app`,
    `skills`, `mcp`, and `info` sub-commands; the REPL streams output,
    shows tool activity, and renders reasoning blocks.
  - `shiny` app (`codeagent_app()`) with tool cards, session management,
    and theme options.
  - MCP server (`codeagent_mcp_server()`, stdio and HTTP) and MCP client
    (`register_mcp_client()`, stdio) for external tool interoperability.
