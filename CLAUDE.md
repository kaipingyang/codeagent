# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

`codeagent` is an R package — an R-native implementation of Claude Code CLI capabilities (harness layer), built on `ellmer` + `btw`. It does **not** wrap the Claude Code CLI subprocess; it reimplements the agent loop, tools, permissions, compaction, skill system, and Shiny UI from scratch.

**Reference docs:** `.claude/docs/` contains learning materials. Read before touching a subsystem.

| File | When to read |
|------|-------------|
| `ellmer-package.md` | Core Chat API, tool(), type_*(), ContentToolResult, S7 internals |
| `ellmer-tool-calling.md` | Tool registration, tool_annotations(), _intent pattern, streaming |
| `shinychat.md` | chat_append(), tool cards, _intent display, ContentToolResult extra$display |
| `btw-package.md` | btw 1.2.1 complete reference: skill system, CLI, agent tools, MCP |
| `shiny-extended-task.md` | ExtendedTask + coro::async streaming pattern used in ui.R |
| `promises-async-r.md` | promises, await(), async/await patterns in Shiny |
| `claude-code-cli-architecture.md` | Claude Code CLI design: compaction, tools, permissions, sessions |

---

## Common Commands

```r
# Document + rebuild NAMESPACE
devtools::document()

# Full R CMD check (target: 0 errors, 0 warnings)
devtools::check()

# Load package interactively
devtools::load_all()

# Run all tests (281 pass as of Batch 3)
devtools::test()

# Run a single test file
testthat::test_file("tests/testthat/test-permissions.R")

# New-style one-shot query (recommended)
library(codeagent)
chat   <- ellmer::chat_openai_compatible(base_url=Sys.getenv("CODEAGENT_BASE_URL"),
           model=Sys.getenv("CODEAGENT_MODEL"), credentials=function() Sys.getenv("CODEAGENT_API_KEY"))
client <- codeagent_client(chat, permission_mode = "bypass")
codeagent(client, "List all .R files in R/")

# Launch Shiny app (new style)
codeagent_app(client, theme = "light")

# From codeagent.md config
client <- codeagent_client_config(alias = "gpt41")
codeagent_app(client)
```

**Non-ASCII in source:** R CMD check rejects non-ASCII characters in R source files. Use `\uXXXX` escapes only inside string literals — **not** in roxygen `#'` comments.

**`coro::for` inside `coro::async`:** Write plain `for (x in gen)` — do not qualify as `coro::for`. Do not wrap in `tryCatch()` inside the loop.

**Env vars:** Use `CODEAGENT_BASE_URL`, `CODEAGENT_MODEL`, `CODEAGENT_API_KEY` (not `OPENAI_*`).

---

## Architecture

### Entry point / data flow

```
User input
  → .preprocess_input()         # detect /skillname
  → load_skill_prompt()         # Level 2 skill load (on demand)
  → agent_loop()                # main agentic turn (was query_loop)
      → .build_system_reminder()  # dynamic per-turn context injection
      → CompactionController$maybe_compact()   # L1-L5
      → ContentReplacementState$maybe_replace()
      → HookRegistry$run_user_message()
      → ellmer Chat$chat() / stream_async(stream="content")
          → tools dispatch (ellmer tool loop)
              → check_permission()         # 7-mode gate
              → HookRegistry$run_pre()     # PreToolUse
              → tool execution             # returns ContentToolResult
              → HookRegistry$run_post()    # PostToolUse
      → verify_fn (optional)    # re-enter if fails
      → HookRegistry$run_assistant_message()
      → save_session()
```

### Client object model

```r
# Step 1: any ellmer Chat (user picks backend)
chat <- ellmer::chat_openai_compatible(...)   # Databricks/Azure
# OR chat <- ellmer::chat_anthropic(...)
# OR chat <- ellmer::chat_ollama(...)

# Step 2: codeagent_client() injects tools + system prompt → CodagentClient
client <- codeagent_client(chat,
  permission_mode    = "bypass",
  btw_groups         = c("docs","git","pkg"),
  worktree_isolation = FALSE,
  verify_fn          = NULL
)
# client$chat    — the ellmer Chat
# client$settings — named list with all config

# Step 3: use the client
codeagent(client, "prompt")          # one-shot
agent_loop(user_input, client, ...)  # per-turn (Shiny)
codeagent_app(client, theme="light") # Shiny UI
```

### Subsystems

**`query.R`** — `codeagent_client()` is the primary factory; builds `CodagentClient` S3 object. `codeagent()` dispatches new/legacy style. `agent_loop()` is called per-turn (was `query_loop`). `.register_all_tools()` wires all tool groups. `.handle_agent_error()` classifies PTL/rate-limit/network/auth errors with backoff. `verify_r_tests()` is a built-in verify function.

**`permissions.R`** — **Seven-mode** gate: `default / plan / accept_edits / bypass / dont_ask / auto / bubble`. `bubble` returns `"ask"` to bubble permission up to parent agent (sub-agent mode). `auto` uses haiku ML classifier. `DenialTracker` emits warnings.

**`hooks.R`** — `HookRegistry` with **7 lifecycle events** via `HookEvent$*`: `PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `PermissionDenied`, `PermissionRequest`, `UserMessage`, `AssistantMessage`. Legacy `register_pre()`/`register_post()` still work.

**`tools_builtin.R`** — 8 core tools (Bash, Read, Write, Edit, MultiEdit, Glob, Grep, LS). All return `ContentToolResult` with `extra$display` (HTML title + markdown) for shinychat tool cards. All have `_intent` parameter for card display.

**`tools_r.R`** — Wraps `btw::btw_tools()`. `.BTW_GROUPS` covers all 10 btw 1.2.1 groups: `agent, cran, docs, env, files, git, ide, pkg, sessioninfo, web`. `btw_tool_skill` excluded (handled by skill system).

**`tools_agent.R`** — `agent_tool()` uses `btw_tool_agent_subagent` when btw available; falls back to codeagent's own loop. Supports `worktree_isolation=TRUE` (git worktree per sub-agent). Discovers custom agents from `.btw/agent-*.md`, `.claude/agents/`. `codeagent_mcp_server()` wraps `btw::btw_mcp_server()`. `install_codeagent_cli()` installs Rapp-based CLI.

**`compaction.R`** — **Five-level** compaction:
- L1 `snip_old_tools`: replace large old tool results with placeholder
- L2 `session_memory_compact`: summarise early turns via compact model
- L3 `full_compact`: fork agent → 9-section `<summary>`
- L4 `ptl_fallback`: drop oldest turns on 413 errors
- L5 `context_collapse`: read-time projection (truncate all tool result values)

**`skills.R`** — **btw-compatible** skill system. Skill format: `<name>/SKILL.md` directories (not flat `.md` files). Uses `btw:::btw_skills_list()` as primary discovery backend. Discovery paths: codeagent `inst/skills/` + btw paths + `~/.codeagent/skills/` + `.codeagent/skills/` + `.claude/skills/` + `.codex/skills/`. `.make_skill_tool()` registers `use_skill` ellmer tool for LLM semantic auto-trigger; returns `ContentToolResult` with HTML title card. Two trigger paths: user `/name` → `load_skill_prompt()` inject; LLM semantic match → `use_skill` tool call.

**`client_config.R`** — `codeagent_client_config(alias=)` reads `codeagent.md` / `.codeagent/config.md`. Supports single client spec (`"openai/model"`) or alias maps with interactive selection. `use_codeagent_md()` creates template.

**`settings.R`** — Priority: env vars > `~/.codeagent/settings.json` > `.codeagent/settings.json` > defaults. `.build_system_reminder()` injects ephemeral per-turn context (date/iteration/cwd) into user message (not system prompt) to preserve prompt cache.

**`compaction.R` `.make_compact_chat()`** — When `CODEAGENT_BASE_URL` set, uses `chat_openai_compatible` with `databricks-claude-haiku-4-5`; otherwise `chat_anthropic`.

**`ui.R`** — `codeagent_app(client, pinned_skills, theme, port, launch.browser)`. Three accordion panels: Sessions (1st, open), Skills (2nd, searchable + scrollable + install), Settings (permission mode + btw tool groups + theme toggle). Three themes: `"light"` (bslib flatly), `"glassmorphism"` (dark purple gradient + frosted glass), `"dark"` (minimal dark). Tools stream via `stream="content"` → shinychat renders tool cards automatically.

**`sessions.R / mutations.R`** — Sessions stored as JSONL under `~/.codeagent/projects/<hash>/`. Session titles fall back to first user message (not UUID). `fork_session()` implemented.

### Key design decisions

- **`codeagent_client()` is the central factory**: takes any ellmer Chat, injects tools + system prompt, returns `CodagentClient`. Both `codeagent()` and `codeagent_app()` accept `CodagentClient` as first arg; old flat params still work for backward compat.
- **btw as tool layer**: codeagent is the harness (loop/permissions/compaction/hooks/skills); btw provides the R-environment tool set (docs/git/pkg/env/etc). They compose, not compete.
- **Skill format is `name/SKILL.md`** (btw/Claude Code compatible). Never use flat `.md` files.
- **`ContentToolResult` with `extra$display`**: all tools return typed results with HTML title + markdown for shinychat cards.
- **S7 slot access is fragile**: wrap in `tryCatch`.
- **`%||%` null-coalescing**: defined in `utils.R`.

### Runtime directories

| Path | Purpose |
|------|---------|
| `~/.codeagent/settings.json` | User-global settings |
| `~/.codeagent/projects/<hash>/` | Session JSONL files |
| `~/.codeagent/tool-results/` | L2 large-result disk cache |
| `~/.codeagent/skills/` | User-global custom skills |
| `.codeagent/skills/` | Project-local skill overrides |
| `.codeagent/config.md` | Project-local multi-client config |
| `codeagent.md` | Project-local multi-client config (alt location) |
| `exec/codeagent.R` | Rapp CLI entry point |

---

## What is implemented

All core subsystems are complete. 281 tests pass.

- ✅ Agent loop (`agent_loop()`) with max_turns, budget, compaction, hooks
- ✅ 7-mode permission system (includes `bubble`)
- ✅ 7-event hook system (`HookEvent$*`)
- ✅ 5-level compaction (L1-L5)
- ✅ Skill system (btw-compatible `name/SKILL.md`, dual trigger)
- ✅ btw integration (10 tool groups + skill + subagent + MCP)
- ✅ Worktree isolation for sub-agents
- ✅ Verification loop (`verify_fn`)
- ✅ system-reminder dynamic injection
- ✅ Enhanced error recovery (PTL/rate-limit/network/auth)
- ✅ Shiny app (3 themes, accordion sidebar, tool cards)
- ✅ Session management (save/load/fork/tag/rename)
- ✅ codeagent.md multi-client config
- ✅ Rapp CLI (`exec/codeagent.R`)
- ✅ MCP server (`codeagent_mcp_server()`)
