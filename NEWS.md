# codeagent (development version)

* **Data Shield now injects protected-dataset schemas into the system prompt**
  (querychat-style ambient visibility). When a shield is active, every
  registered dataset's *filtered* schema (the same output `DescribeData`
  produces -- identifier values suppressed, rare categories hidden) is placed in
  a `<protected-data>` block in the system prompt, so the model knows what
  protected data exists and its column structure without having to call
  `DescribeData` first (previously it would fabricate column names/dims when it
  didn't call the tool). The `DescribeData` tool is retained as the live,
  on-demand fallback. **Behavior change**: existing shielded clients now get a
  longer system prompt. Data registered *before* the client is built is in the
  initial prompt automatically; for data registered/uploaded at runtime, call
  the new exported `refresh_data_shield_context(client)` after `register_data()`
  (e.g. in a Shiny upload handler) to rebuild the system prompt with the new
  dataset -- this preserves conversation history and only costs a one-time
  prompt-cache miss. `register_data()` deliberately does **not** auto-refresh,
  keeping the shield decoupled from the Chat. Scope note: this is edge-1
  *visibility* only; switching a dataset's security mode mid-conversation is a
  non-goal (the context window is immutable -- the correct reset is a fresh
  conversation).

* **Output gate (edge 3): Data Shield now scans the model's final reply before
  it reaches the user.** Data Shield previously guarded the two edges *into* the
  model (edge 1 input gate, edge 2 tool gate) but not the reply *out* to the
  user -- so a model that reproduced a protected value it inferred from tool
  output (an aggregate edge 2 let through) leaked it even when the user's own
  input was clean. The output gate (`R/output_gate.R` `.output_gate_scan()` +
  `DataShield$scan_response()`) closes this, reusing the same value_match + PII
  detectors as the input gate (audited under `edge = "response"`). CLI
  (`agent_loop`) is non-streaming and **redacts the reply in place**; the Shiny
  app streams token-by-token so it scans the finished reply and **appends a
  warning below** (the text is already on screen). Configurable via
  `settings$data_shield_response_on_fail` (`redact`/`block`/`ask`) and
  `settings$data_shield_output_scanners`. This brings Data Shield to the
  canonical three-edge coverage (input / tool / output), matching the output
  rail of NeMo Guardrails / the Output Guard of Guardrails AI.

* **Input and output gates take a configurable scanner list.**
  `settings$data_shield_input_scanners` / `data_shield_output_scanners` (default
  `c("value_match", "regex")` -- secure-by-default) let a host drop a detector,
  e.g. `c("value_match")` to keep registered-value matching but skip PII regex.
  Backed by a new `scanners=` argument on `DataShield$scan_prompt()` (default
  runs both, fully backward compatible).

* **Input gate (edge 1): Data Shield now scans all user input before it
  reaches the model.** Previously Data Shield only guarded tool traffic (edge 2:
  `scan_ingress`/`scan_egress`); the user's own message went to the model
  unscanned. The input gate (`R/input_gate.R` `.input_gate_scan()`) adds edge-1
  protection over **all input**: typed text and text-bearing attachments are
  scanned via `DataShield$scan_prompt()` (registered protected value pasted in
  via value_match O(1) hash lookup + PII/token shapes via regex), and by default
  it **redacts only the matched spans while keeping the rest of the user's text**
  (`on_fail = "redact"`/`"block"`/`"ask"`). Image attachments are a blind spot by
  default; an optional `data_shield_image_scanner` hook (default `NULL`) lets a
  host inject an OCR/VLM scanner. A `on_progress` callback lets a UI show
  "scanning data safety…". Wired at the UserPromptSubmit point of **both** entry
  paths — the agent loop (CLI) and the Shiny stream. Two systems stay separate:
  the UserPromptSubmit **hook** may block/append but never redacts (CC parity);
  the Data Shield **input gate** may redact (its confidentiality job).

* **`data_shield_ocr_scanner()`: an opt-in OCR image scanner for the input
  gate.** Closes the image blind spot for text baked into screenshots: it OCRs
  the attachment with the optional \pkg{tesseract} package (a `Suggests` dep),
  then runs the extracted text through `scan_prompt()`, blocking the turn on a
  protected-value hit. Opt-in (scheme A) — the default
  `data_shield_image_scanner` stays `NULL`; wire it explicitly via
  `settings$data_shield_image_scanner = data_shield_ocr_scanner(shield)`. When
  \pkg{tesseract} is not installed the scanner degrades to `pass` (never blocks
  on a missing optional dep).

* **The input gate now also runs on the Shiny app's real stream path**
  (`server_chat.R` `stream_task`), not only the standalone
  `codeagent_stream_async()`. Uploaded attachments and typed text in the app are
  scanned at edge 1 before reaching the model; a block ends the turn with a chat
  message, a redact continues with the sanitized input.

* **`UserPromptSubmit` hook can now block or add context** (was notify-only).
  Renamed `UserMessage` -> `UserPromptSubmit` to align with Claude Code's public
  hook event name. A hook may return `action = "block"` (the prompt never
  reaches the model) or `"add_context"` (append text to what is sent) -- never
  rewrites the user's original wording, matching CC's contract. `run_user_message`
  -> `run_user_prompt_submit`.

* **Hooks aligned with Claude Code's 27 lifecycle events** (was 12). Events
  with a real trigger fire live: `SessionEnd`, `PostCompact`, `StopFailure`,
  `Notification`, `TaskCreated`/`TaskCompleted` (through the TaskCreate/TaskUpdate
  tools), and `InstructionsLoaded` (replayed from the loaded CLAUDE.md files).
  `FileChanged`/`ConfigChange` are driven by the `watcher` package and work in
  BOTH the Shiny app and the CLI REPL -- the prompt reads keys non-blockingly so
  an idle session still dispatches filesystem-watch callbacks (needs `watcher`
  installed; no-op otherwise). Remaining CC events are defined for a complete
  allowlist but have no live trigger yet (`Elicitation`/`ElicitationResult` need
  MCP elicitation; `TeammateIdle`/`Setup`/`CwdChanged` have no matching phase;
  `WorktreeCreate`/`WorktreeRemove` deferred until cross-process team events).
  `AssistantMessage` stays notify-only (Claude Code has no such event).


* **Bounded value-match index**: `register_data(max_index_values=)` caps the
  value-match hash index (default 500000 values, ~65MB of keys). Benchmarked on
  open-source CDISC-ADaM-format example data from the {pharmaverse} project
  (`inst/bench/value_match_benchmark.R`): index memory grows linearly and
  unbounded (~130MB / 1M values), so on overflow indexing stops and a warning
  is emitted; unindexed values rely on the other egress layers. Zero false
  positives on ordinary clinical prose and pharmaverse-format USUBJID/SUBJID
  caught, so the min_len/min_card thresholds are unchanged.

* **Column-level raw access**: `register_data(column_access=)` grants per-column
  raw access on a protected data.frame (e.g. a public `TESTCD` codelist beside
  protected columns), reusing the asset `none`/`schema`/`scan`/`raw` levels split
  into `prompt`/`egress`. `prompt="raw"` makes `DescribeData` enumerate the real
  values (no k-anonymity suppression); `egress="raw"` drops the column from the
  value-match index. A raw edge requires a non-empty `reason`; an override
  missing it is dropped with a warning and the column falls back to its
  sensitivity tier (fails safe). `coverage()$raw_access_columns` counts overrides.

* **Extensible ingress blacklist**: built-in `shield_ingress()` rules moved to a
  grouped `.DATA_SHIELD_INGRESS_RULES` constant and expanded (pandas `to_*`, more
  R writers, `urllib`/`httpx`/`aiohttp`, `nc`/`scp`/`rsync`/`/dev/tcp`, inline
  `-e`/`-c` eval). A `patterns=` name matching a built-in now **replaces** that
  rule (was append-only); new names are added. Hosts wanting file-managed
  blacklists read their own file into a named vector and pass it via `patterns=`.

* **Small-model semantic code reviewer**: new `shield_reviewer()` is an optional
  internal ingress rail (never a model-callable tool). It reviews only
  deterministic PII/value-sanitized tool code/arguments with a fresh, tool-less,
  history-free ellmer Chat. Explicit `client_factory` wins; otherwise the parent
  provider is reused with `CODEAGENT_FAST_MODEL` (never silently the main model).
  Scope defaults to exec/write/net; risk/error independently choose ask/block;
  async turns await a timed promise. Structured JSON parsing and reviewer
  failures fail closed. Remote mode never receives raw data/output; raw review is
  reserved for an explicit future local-only egress mode.

* **Data Shield egress approval**: `shield_egress(on_fail="ask")` pauses after a
  local tool executes but before its result reaches the LLM. Default choices are
  Redact/Block; dangerous `ALLOW RAW ONCE` appears only with explicit
  `allow_raw_approval=TRUE` and never changes future policy. CLI uses synchronous
  selection; Shiny uses a promise-backed three-button interaction. Missing
  callbacks, invalid choices, errors and timeouts default to redact. Approval
  payloads/audit contain metadata only, never the raw result.

* **Portable sandbox policy**: new `shield_sandbox()` keeps project/session-temp
  `rwx` and process execution by default while the central gate validates all
  explicit path arguments against project/protected/temp roots, follows real
  paths to reject symlink escape, enforces per-root `r/rw/rwx`, and can deny
  network/exec capabilities. `backend="auto"` honestly falls back to policy (or
  blocks in required mode) because a full OS process adapter is not yet wired;
  coverage/audit report the fallback. btw file tools are also covered (their cwd
  guard permits symlink escape), and btw RunR is not treated as an OS sandbox.

* **Per-tool/agent Shield policy**: new `shield_tool_policy()` supports exact or
  `*`-glob rules with `scan` (default), explicit audited `bypass`, and `deny`
  independently for execution, ingress and egress. Trusted tools such as KMPlot
  may bypass only egress while retaining ingress scans; deny blocks execution.
  Shield bypass never bypasses the separate central permission gate.

* **Data Asset Policy** separates what an asset is (`kind`: dataset/spec/
  document/synthetic) from what the LLM may see (`llm_access`: prompt/egress
  none/schema/scan/raw). Kind-specific defaults keep datasets schema-only while
  allowing specs/synthetic prompt content; egress never defaults raw. Raw access
  requires a reason, is session-scoped with optional expiry, is audited, and
  requires explicit provenance via `$trusted_result()`. Synthetic/raw always
  runs baseline PII/secret regex; spec/raw may explicitly disable it.

* **Non-sensitive Data Shield audit log**: every blocked/asked ingress decision
  and redacted/blocked egress event records timestamp, edge, tool name/call id,
  strategy, action, reason label, match count and score in the owning R6
  instance. Raw tool arguments/results, matched values, span text, rows and
  hashes are never stored. Use `$audit(limit=)`, `$clear_audit()`, and
  `$coverage()$audit_events`; `audit_max` bounds memory with oldest-first
  eviction.

* **Universal Data Shield ingress scanning**: new `shield_ingress()` scans the
  arguments of every native/btw/MCP/host tool inside the single central
  permission gate before execution. High-confidence R/Python/Bash serialization,
  encoded output, network exfiltration, shell data-file display, registered-data
  preview calls, and custom PCRE rules may `block` or force the existing `ask_fn`
  approval UI. Read-only/unknown tools no longer bypass a Shield-forced ask;
  without a Shield, permission behaviour is unchanged.

* **Composable egress scanners**: `DataShield` now executes an ordered scanner
  pipeline (list order = execution order) and supports runtime
  `$add_scanner(name, fn)`. New `shield_regex()` redacts or blocks unregistered
  email, phone-like values, common API-token prefixes, 18-character identity
  numbers, and custom named PCRE patterns. Scanner contracts are validated and
  fail closed; no custom S7 or Python dependency is introduced.

* **Data Shield recursively covers foreground sub-agents**: synchronous and
  concurrent `Agent` sub-chats inherit the parent `DataShield` before their first
  model request, and uninstrumented btw/custom-agent delegation is skipped.
  `BackgroundAgent` and `/bg` fail closed while a shield is active because a
  separate mirai process cannot safely inherit the session's R6/index yet.

* **Multi-user Shiny isolation**: `codeagent_app(client_factory = function(session) ...)`
  now creates a fresh `CodeagentClient`/Chat inside every Shiny session; the
  no-client default uses this safe path automatically. Passing a pre-built
  `client` remains the explicitly single-user compatibility path. Data Shield
  protected values live in a session/thread-owned `DataShield` R6 that may be
  shared deliberately without any package-global index.

* **Data Shield P0/P0.5/P1 (opt-in, default OFF)** is now a single stateful
  `DataShield` R6 engine. The easy `data_shield=list(shield_*())` form creates a
  private R6; pass an explicit `DataShield$new()` to register uploads or share a
  policy across selected chats. `shield$install(chat)` wraps tool results;
  `shield$register_data()` builds high-entropy value indexes; `shield$describe()`
  powers the automatically installed strict `DescribeData` tool. Bulk rows and
  targeted protected values are withheld; metadata exposes no distributions,
  counts, raw rows, or free-text examples. Scanner specs remain plain R
  functions/lists (no custom S7).

* **Backend permission gate for host tools**: new exported
  `install_permission_gate(chat, permission_mode, rules, tools, ask_fn, tool_meta)`
  lets a harness-only client (`register_tools = FALSE`) put the central
  permission gate over host-attached tools (the gate is otherwise only installed
  by `.register_all_tools()`). The gate now also passes the tool-call `id` to
  `ask_fn`s that accept it (`ask_fn(name, input, id = NULL)`), so hosts can match
  an approval prompt to the `on_tool_request` preview; legacy `(name, input)`
  `ask_fn`s are unchanged.

* **Backend embedding (Contract v1)**: documented, stable surface for hosting
  codeagent as a backend engine. New exported `register_tool_meta(name,
  capability)` lets host apps declare a custom tool's capability
  (`read`/`write`/`exec`/`net`) so the central permission gate governs it (an
  undeclared tool previously defaulted to `read` and was allowed ungated). New
  exported `tool_result(value, kind, payload)` builds a typed display card
  (`text`/`table`/`image`/`code`/`diff`/`error`) that reaches the
  `on_tool_result$display` callback and the Shiny app. Adds the
  `backend-integration` vignette + a reference example
  (`inst/examples/backend_integration_demo.R`) + a contract guard test.

* **Concurrent sub-agents (opt-in via `settings$async_subagents`, default OFF)**:
  the `Agent` tool can run asynchronously so multiple sub-agent delegations
  requested in a single turn execute concurrently (via ellmer's
  `tool_mode = "concurrent"`) on the async streaming paths (CLI REPL / Shiny
  app). Sync one-shot `codeagent()` transparently falls back to sequential
  sub-agents, since async (promise-returning) tools are invalid under
  `Chat$chat()`. Also adopts ellmer 0.4.2 (`set_model()`, `chat_posit()`).

* **Background sub-agents (opt-in via `settings$background_agents`, default OFF;
  requires `mirai`)**: a new `BackgroundAgent` tool delegates a task to a
  fire-and-forget sub-agent running in a `mirai` daemon and returns immediately
  (non-blocking). Its result is polled and surfaced back to the model on a later
  turn via the system reminder, mirroring Claude Code's async agents. Users can
  also spawn and inspect background agents directly with the `/bg <task>` and
  `/bgstatus` slash commands (REPL and Shiny).

# codeagent 0.1.0

First public release. `codeagent` is an R-native reimplementation of a
command-line coding agent, built on `ellmer` and `btw`. It provides the agent
harness (loop, tools, permissions, compaction, hooks, skills) plus a CLI REPL
and a `shiny` user interface.

## Model tier env var rename — breaking changes

Three environment variables have been renamed to remove vendor-specific names.
Update your `.Renviron` / `settings.json` env block accordingly:

| Old | New | Meaning |
|-----|-----|---------|
| `CODEAGENT_DEFAULT_SONNET_MODEL` | `CODEAGENT_MODEL` | Everyday main model |
| `CODEAGENT_DEFAULT_OPUS_MODEL` | `CODEAGENT_HEAVY_MODEL` | High-capability model |
| `CODEAGENT_SMALL_FAST_MODEL` | `CODEAGENT_FAST_MODEL` | Cheap/fast model |

Tier aliases used in `/model` and `codeagent.md` also changed:
`"sonnet"` → `"main"`, `"opus"` → `"heavy"`, `"haiku"` → `"fast"`.

`CODEAGENT_MODEL` now serves dual purpose: it sets both the default model and
the `"main"` tier alias (previously `CODEAGENT_MODEL` and
`CODEAGENT_DEFAULT_SONNET_MODEL` were separate; they are now merged).

## CLI/ink unified entry point — breaking changes (plan #20)

* **Default permission mode is now `"default"`** across all entry points (CLI,
  Shiny, ink). Previously all CLI subcommands defaulted to `"bypass"`. Write
  operations (file edits, shell commands) now prompt for approval unless you
  explicitly opt into bypass mode.

* **`-y` / `--yolo`** — new global flag for the CLI that enables bypass mode
  (skips all permission prompts). Equivalent to Claude Code's
  `--dangerously-skip-permissions`. Short-hand: `-y`.

  ```
  codeagent -y           # bypass REPL
  codeagent app -y       # bypass Shiny app
  codeagent run "q" -y   # bypass one-shot query
  ```

* **`codeagent` without a subcommand** now starts the interactive REPL directly
  (equivalent to `codeagent chat`). Previously a subcommand was required.

* **`-p` / `--print-mode`** — new flag for one-shot non-interactive output.
  `codeagent "query"` or `codeagent -p "query"` runs a single query and exits.

* **`-m` now means `--model`** (breaking). The old `-m`/`--mode` alias has been
  removed. Use `-y`/`--yolo` for bypass mode instead.

* **`ink_ui()` gains `yolo = FALSE`** parameter. When `TRUE`, sets `INK_YOLO=1`
  so the codeagent backend runs in bypass mode. The `inkai` terminal command
  also accepts `-y`/`--yolo`.

  ```
  ink_ui("codeagent", yolo = TRUE)   # bypass
  # or from terminal:
  inkai codeagent -y                 # bypass
  ```

* **`INK_YOLO` env var** — set to `"1"` to enable bypass mode in ink when
  launching the `inkai` command directly: `INK_YOLO=1 inkai codeagent`.

* **`codeagent_app(permission_mode = "default")` unchanged** — Shiny was already
  correct; pass `permission_mode = "bypass"` explicitly when needed.

* **`R/cli_dispatch.R`** — new internal helpers `.ca_resolve_mode()` and
  `.ca_dispatch()` expose CLI dispatch logic as testable pure functions.

### Migration guide

| Old | New |
|-----|-----|
| `codeagent chat` | `codeagent` |
| `codeagent chat -m bypass` | `codeagent -y` |
| `codeagent -m bypass` | `codeagent -y` |
| `ink_ui("codeagent")` (was bypass) | `ink_ui("codeagent", yolo = TRUE)` for bypass |
| `inkai codeagent` (was bypass) | `inkai codeagent -y` for bypass |

## Unified agent streaming API (plan #19)

* **`codeagent_stream_async()`** — new exported function. Streams one agent
  turn asynchronously (`coro::async` promise). Runs the full turn pipeline
  (compaction, system-reminder injection, session save, cost tracking via
  `get_cost(include="last")`). Fires typed callbacks: `on_delta`, `on_thinking`,
  `on_tool_request` (pre-gate, from stream chunk), `on_tool_result` (with typed
  `display` contract from `.adapt_tool_result()`), `on_error`, `on_usage`.
  Supports `stream_controller` for cancellation and `tool_mode` for concurrent
  tool execution.

* **`codeagent_stream()`** — synchronous wrapper around `codeagent_stream_async()`
  using `later::run_now()` to pump the event loop. Handles Ctrl+C gracefully
  (cancels the stream via `stream_controller`, does not re-throw the interrupt
  condition). Intended for CLI and ink frontends.

* **Turn pipeline helpers** (`R/turn_pipeline.R`, internal):
  `.turn_setup()` consolidates compaction + resource replacement + system-reminder
  injection into one call. `.turn_teardown()` consolidates session save + usage +
  `cost_last`. Both are now shared by console, Shiny, and ink.

* **Shiny system-reminder injection fixed.** `server_chat.R`'s `stream_task` now
  injects the `<system-reminder>` block (date/iteration/cwd/memory) on every
  turn, matching the behaviour of the console REPL and `agent_loop()`.

* **Console Ctrl+C repair.** `codeagent_console()` now creates a
  `stream_controller` per turn and catches `interrupt` conditions, cancelling
  the stream gracefully. Previously Ctrl+C could corrupt the chat state.

* **Callback deduplication.** `.register_repl_tool_callbacks()` is now guarded
  by `.chat_once()` to prevent stacking display callbacks if `codeagent_console()`
  is called more than once on the same chat object.

* **`.patch_interrupted_chat()` retired.** Removed from all call sites. ellmer
  0.4.0+ (#840) and 0.4.1+ (#643) handle orphaned tool requests and
  `AssistantPartialTurn` automatically.

* **`inkAssistantUI` tool cards upgraded.** `ink_reply_stream()` now calls
  `codeagent_stream()` when available (full turn pipeline + display contract).
  `on_tool_result` receives a rich `display` field (title/kind/payload) instead
  of a plain string. The `ink_server()` initialises per-session
  `CompactionController` / `ContentReplacementState` / `session_id` so turns
  are properly managed.

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
