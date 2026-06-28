# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

`codeagent` is an R package — an R-native implementation of Claude Code CLI capabilities, built directly on the Anthropic API via `ellmer`. It does **not** wrap the Claude Code CLI subprocess; it reimplements the agent loop, tools, permissions, compaction, and UI from scratch.

**Reference docs:** `.claude/docs/` contains learning materials on ellmer, shinychat, btw, coro/side patterns, and Claude Code architecture. Read these before touching a subsystem.

| File | When to read |
|------|-------------|
| `ellmer-package.md` | Core Chat API, tool(), type_*(), ContentToolResult, S7 internals |
| `ellmer-tool-calling.md` | Tool registration, tool_annotations(), _intent pattern, streaming |
| `shinychat.md` | chat_append(), chat_append_stream(), tool cards, _intent display, tool_annotations title/icon, ContentToolResult extra$display |
| `btw-package.md` | Reference implementation: tool card titles, _intent, ContentToolResult display, wrap_with_intent pattern |
| `shiny-extended-task.md` | ExtendedTask + coro::async streaming pattern used in ui.R |
| `promises-async-r.md` | promises, await(), async/await patterns in Shiny |
| `shiny-realtime-update-blocking-loop.md` | Non-blocking streaming, interrupt patterns |
| `claude-code-cli-architecture.md` | Claude Code CLI design: compaction, tools, permissions, sessions |
| `side-package-learnings.md` | coro generator patterns, for-loop in async context |

---

## Common Commands

```r
# Document + rebuild NAMESPACE
devtools::document()

# Full R CMD check (target: 0 errors, 0 warnings)
devtools::check()

# Load package interactively
devtools::load_all()

# Run all tests (none yet — tests/testthat/ is empty)
devtools::test()

# Run a single test file
testthat::test_file("tests/testthat/test-permissions.R")

# One-shot query (non-interactive, bypass mode for dev)
library(codeagent)
codeagent("List all .R files in R/", permission_mode = "bypass")

# Launch Shiny app
codeagent_app(permission_mode = "bypass")
```

**Non-ASCII in source:** R CMD check rejects non-ASCII characters in R source files. Use `\uXXXX` escapes only inside string literals — **not** in roxygen `#'` comments (those get copied to `.Rd` and the `\u` escape is not valid there). Use plain ASCII in comments.

**`coro::for` inside `coro::async`:** Write plain `for (x in gen)` — do not qualify as `coro::for`. Wrapping a `for` loop over an async generator in `tryCatch()` is a parse error; handle errors outside the loop.

---

## Architecture

### Data flow

```
User input
  → .preprocess_input()      # detect /skillname args
  → load_skill_prompt()      # Level 2 skill load (on demand)
  → query_loop()             # main agentic turn
      → CompactionController$maybe_compact()
      → ContentReplacementState$maybe_replace()
      → ellmer Chat$chat() / stream_async()
          → tools dispatch (ellmer handles tool loop internally)
              → check_permission()  ← permission gate
              → HookRegistry$run_pre()
              → tool execution
              → truncate_tool_result() / persist_large_result()
              → HookRegistry$run_post()
      → save_session()
```

### Subsystems

**`query.R`** — Entry points. `codeagent()` is the one-shot console API. `query_loop()` is called per-turn by the Shiny app. `.register_all_tools()` wires all tool groups onto a Chat object.

**`permissions.R`** — Six-mode gate (`default / plan / accept_edits / bypass / dont_ask / auto`). Every tool factory calls `.make_permission_checker()` which closes over `check_permission()`. The `auto` mode calls claude-haiku-4-5-20251001 as a classifier. `DenialTracker` emits warnings at 3 consecutive / 20 total denials.

**`tools_builtin.R`** — Eight core tools (Bash, Read, Write, Edit, MultiEdit, Glob, Grep, LS). Each is a factory function `*_tool(mode, rules, ask_fn)` returning an `ellmer::tool()` object. `register_builtin_tools()` registers all eight. The permission checker is injected as a closure at construction time.

**`tools_web.R / tools_task.R / tools_notebook.R / tools_agent.R / tools_r.R`** — Additional tool groups. Task tools use an in-process `new.env()` store (`.task_store`) — not persisted. `tools_r.R` wraps `btw::btw_tools()` and supports group-level filtering.

**`compaction.R`** — Four-level compaction triggered at `model_limit − 33K` tokens. L1 (`snip_old_tools`) replaces large old tool results with a placeholder. L2 (`session_memory_compact`) summarises early turns via haiku. L3 (`full_compact`) forks a haiku agent to generate a 9-section `<summary>`. L4 (`ptl_fallback`) drops oldest turns on 413 errors. `CompactionController` has a 3-failure circuit breaker. `estimate_tokens()` uses a char÷4 heuristic — it accesses `turn@contents` (S7 slot) inside `tryCatch` to survive ellmer API changes.

**`resource.R`** — Three-layer output size control. L1 is `truncate_tool_result()` in `utils.R` (applied at tool execution). L2 `persist_large_result()` saves results >5 KB to `~/.codeagent/tool-results/`. L3 `ContentReplacementState` replaces the largest old `ContentToolResult` in the turn history when context exceeds 80K estimated tokens.

**`budget.R`** — `BudgetTracker` stops the loop at 90% of `max_tokens`, or after 3 consecutive turns with <500-token growth (diminishing-return detection). Sub-agents are exempt.

**`executor.R`** — `StreamingToolExecutor` classifies tools as concurrent-safe (read-only) or not. Safe tools run immediately; unsafe tools queue and execute serially. Bash read-only detection re-uses `.is_bash_readonly()` from `permissions.R`.

**`hooks.R`** — `HookRegistry` stores pre/post hooks with optional tool-name glob patterns. Pre-hooks can allow, deny, or replace `tool_input`. Post-hooks can replace `tool_output`. Hooks >500 ms log a message; >2000 ms emit a warning.

**`skills.R`** — Two-level progressive disclosure. Level 1: `list_skills_meta()` reads only YAML frontmatter (first 30 lines) from `.md` files — keeps system prompt small. Level 2: `load_skill_prompt()` reads full body + substitutes `$ARGUMENTS` / `$ARG1`. Discovery order: `inst/skills/` → `~/.codeagent/skills/` → `.codeagent/skills/` (project-local overrides package built-ins).

**`settings.R`** — Priority chain: env vars (`CODEAGENT_MODEL`, `CODEAGENT_PERMISSION_MODE`, `CODEAGENT_MAX_TURNS`, `CODEAGENT_MODEL_LIMIT`) > `~/.codeagent/settings.json` > `.codeagent/settings.json` > defaults. `CLAUDE.md` is loaded as context (injected into system prompt), not merged as settings. `.build_system_prompt()` assembles: identity + cwd/date/model + CLAUDE.md content + skill hint (≤1000 tokens) + permission mode.

**`sessions.R / mutations.R`** — Sessions stored as JSONL under `~/.codeagent/projects/<sanitized-path-hash>/`. Format: first line is a `session-start` header with `cwd`, `model`, optional `customTitle`; subsequent lines are `user`/`assistant` entries. `mutations.R` is append-only (`rename_session`, `tag_session`, `delete_session`). **Note:** this format is NOT compatible with Claude Code CLI's `~/.claude/projects/`.

**`ui.R`** — `codeagent_app()` builds a `bslib::page_fillable` layout with a sidebar (token budget, permission mode selector, session list) and a `shinychat::chat_ui`. Streaming uses `shiny::ExtendedTask` + `coro::async`. The ESC key sets an `interrupt_flag` reactive which is checked inside the `for (chunk in stream)` loop. The `chat` object is created once at app startup and shared across the session via closure.

### Key design decisions

- **ellmer handles the agentic tool loop**: `chat$chat()` automatically iterates tool calls until `stop_reason == "end_turn"`. `query_loop()` wraps a single turn, not an inner loop.
- **Tool factories close over permissions**: Each `*_tool()` function captures `mode`, `rules`, and `ask_fn` at construction. Changing permission mode after tool registration requires calling `.register_all_tools()` again (as done in `ui.R`'s `observeEvent(input$perm_mode, ...)`).
- **S7 slot access is fragile**: `turn@contents`, `c@text`, `c@value`, `c@tool_use_id` are ellmer internals. All accesses use `tryCatch(..., error = function(e) ...)` to silently fail if ellmer's S7 schema changes.
- **`%||%` is the null-coalescing operator**: defined in `utils.R`, used throughout.

### Runtime directories

| Path | Purpose |
|------|---------|
| `~/.codeagent/settings.json` | User-global settings |
| `~/.codeagent/projects/<hash>/` | Session JSONL files |
| `~/.codeagent/tool-results/` | L2 large-result disk cache |
| `~/.codeagent/skills/` | User-global custom skills |
| `.codeagent/settings.json` | Project-local settings override |
| `.codeagent/skills/` | Project-local skill overrides |

---

## What is not yet implemented

- `tests/testthat/` — no tests exist yet
- `fork_session()` in `mutations.R`
- Tool approval dialog in `ui.R` (permission `"ask"` silently denies in Shiny)
- `inst/www/styles.css` and `inst/www/agent.js`
- `grep_tool` `output_mode = "files_with_matches"` and `"count"` modes
- Session list sidebar load buttons (`load_sess_*`) have no `observeEvent` binding
- MCP server integration via `mcptools`
