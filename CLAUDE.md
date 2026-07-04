# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

`codeagent` is an R package — an R-native implementation of Claude Code CLI capabilities (harness layer), built on `ellmer` + `btw`. It does **not** wrap the Claude Code CLI subprocess; it reimplements the agent loop, tools, permissions, compaction, skill system, and Shiny UI from scratch.

**Reference docs:** `.claude/docs/` contains learning materials. Read before touching a subsystem.

| File | When to read |
|------|-------------|
| `ellmer-package.md` | Core Chat API, tool(), type_*(), ContentToolResult, S7 internals |
| `ellmer-tool-calling.md` | tool(), type_*(), ContentToolResult extra$display, tool_annotations(), on_tool_request/result, stream="content" |
| `btw-package.md` | btw 1.2.1 overview, client config, skill system |
| `btw-tools.md` | btw 工具组完整参考（10组 + skill系统 + btw_app设计）|
| `shinychat.md` | chat_append(), tool cards, _intent display, ContentToolResult extra$display |
| `bslib-shinychat-layout.md` | `chat_ui(fill=TRUE)`、`page_fillable()`、`layout_sidebar()`、`sidebar(fillable=TRUE)` 的真实约束；先读再改聊天布局 |
| `bslib-toolbar-toast.md` | `toolbar()` / `toolbar_input_button()` / `toast()` 在本项目中的推荐用法 |
| `bslib-toast-vs-notification.md` | `bslib::show_toast()` 与 `shiny::showNotification()` 的选型结论 |
| `shinyAssistantUI-grouping.md` | slash command / action item 的固定 6 分组：`Context` / `Model` / `Customize` / `Slash Commands` / `Settings` / `Support` |
| `btw-package.md` | btw 1.2.1 complete reference: skill system, CLI, agent tools, MCP |
| `shiny-extended-task.md` | ExtendedTask + coro::async streaming pattern used in ui.R |
| `promises-async-r.md` | promises, await(), async/await patterns in Shiny |
| `claude-code-cli-architecture.md` | Claude Code CLI design: compaction, tools, permissions, sessions |

---

## Development Rules

**安全铁律 — 绝不提交/推送/打印敏感数据：** 真实 API key / token / 密码，以及具体基础设施端点
（真实 `base_url`、Databricks/serving-endpoint 主机、workspace ID/host 如 `adb-<id>.azuredatabricks.net`、
内网 hostname/IP）**绝不能**出现在被 git 跟踪的文件（源码/测试/示例/文档/模板）里。示例一律用占位符
（`YOUR-WORKSPACE.cloud.databricks.net`、`sk-...`、`<workspace-id>`），真实值只放 `.Renviron`/keyring
（git 忽略）。`git add/commit/push` 前扫描 diff（`git diff --cached | grep -iE 'api[_-]?key|token|secret|sk-|ghp_|dapi|azuredatabricks\.net|serving-endpoints'`）；
打印 remote URL 时用 `sed -E 's#//[^@]*@#//***@#g'` 掩码，**绝不回显完整 token**。详见 skill `no-secrets`。

**每次改完代码必须重装包并更新 codegraph：**
```r
pak::local_install(".", ask = FALSE, upgrade = FALSE)
```
```bash
codegraph sync   # 更新符号索引，让 kiro/AI 工具看到最新代码
```
这确保 `codeagent chat` / `codeagent_app()` 等用安装版运行的入口点使用最新代码。`devtools::load_all()` 只在当前 R session 里生效，launcher（`--vanilla`）和 CLI 用的是已装的包。codegraph 不会自动同步，手动 sync 后 kiro 的 codegraph 审核才能看到新符号。

**新增功能必须同步更新 README.md：**
- 新导出函数/新 feature → 在 README 对应 section 补一行
- 重要行为变更 → 更新 README 相应描述
- README 79 commits 不更新已是教训：每次 commit 前检查 README 是否需要同步

**改代码必须同步更新测试和 example：**
- 新增/修改函数 → 对应 `tests/testthat/test-*.R` 补测试
- 修改公开 API（签名/行为）→ 对应 `inst/examples/demo_*.R` 或 `test_databricks.R` 更新
- 新功能 → 加进 `inst/examples/test_databricks.R` 的 section
- **新增任何导出函数，必须同时：① 确认是否需接入 `.register_all_tools()`/调用链；② 同步写 `test-*.R` 覆盖主路径和降级路径。**

**工具函数用闭包工厂模式：**
```r
# 正确：外部资源（connection、checker）通过工厂函数捕获
my_tool <- function(con, mode = "bypass") {
  force(con)
  checker <- .make_permission_checker("MyTool", mode, list(), NULL)
  ellmer::tool(
    fun = function(query) {
      if (!checker(list(query = query))) return("[Permission denied]")
      dbGetQuery(con, query)  # con 在闭包里
    },
    description = "...",
    arguments   = list(query = ellmer::type_string("SQL query"))
  )
}
# 参考：BIP_copilot/R/tool_run_sql.R — tool_run_sql(con) 模式
```

---

**依赖包版本（当前已装）：**
- `ellmer` 0.4.1.9000（dev，需 `Remotes: tidyverse/ellmer`，CRAN 0.4.1 缺 `set_model()`）
- `btw` 1.3.0.9000（dev，含 `btw_tool_files_patch` 原子多文件编辑）
- `shinychat` 0.4.0.9000（dev，monorepo，安装路径：`pak::pak("posit-dev/shinychat/pkg-r")`，注意不是 `pak::pak("posit-dev/shinychat")`）
- `mcptools` 0.2.1（CRAN）

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
codeagent_app(client, theme = "default")

# From codeagent.md config
client <- codeagent_client_config(alias = "gpt41")
codeagent_app(client)
```

**Non-ASCII in source:** R CMD check rejects non-ASCII characters in R source files. Use `\uXXXX` escapes only inside string literals — **not** in roxygen `#'` comments.

**`coro::for` inside `coro::async`:** Write plain `for (x in gen)` — do not qualify as `coro::for`. Do not wrap in `tryCatch()` inside the loop.

**No `x <- if (...)` inside a `coro::async` body:** coro rewrites `if` as control flow and
**cannot assign the result of an `if` expression** (fails with coro `expr_info`: "Can't
assign the result of a `if` expression"). Assign inside each branch instead
(`if (cond) { x <- a } else { x <- b }`), or compute the value *before* the async body.
Likewise avoid bare `!!!` splicing inside a coro body — use `do.call()`. Also: `coro::async()`
takes a **literal** anonymous function (it `substitute()`s the arg), so you cannot wrap a
dynamically-built function with it — return a `promises::then()` promise from a plain function
instead (ellmer's `invoke_tools_async()` awaits any returned promise). See
`lessons/2026-07-03-shiny-async-interaction.md` and `R/tools_builtin.R` `.asyncify_gated_tool()`.

**Env vars:** Use `CODEAGENT_BASE_URL`, `CODEAGENT_MODEL`, `CODEAGENT_API_KEY` (not `OPENAI_*`).

**Shiny layout rule:** Before changing chat/sidebar layout, read `~/.claude/docs/bslib-shinychat-layout.md`. In particular, `shinychat::chat_ui(fill = TRUE)` must live inside a truly fillable parent (for example `bslib::sidebar(fillable = TRUE, ...)`), and extra wrappers often break sticky-bottom input behavior.

**Shiny component rule:** Prefer `bslib::toolbar()` for compact action rows and prefer `bslib::show_toast()` over `shiny::showNotification()` for user-facing status feedback. Read `~/.claude/docs/bslib-toolbar-toast.md` and `~/.claude/docs/bslib-toast-vs-notification.md` before introducing new action bars or notifications.

**Shiny state rule:** Use a single `shiny::reactiveValues()` for shared session state (see `ui.R` `state <- reactiveValues(...)`). Do NOT scatter individual `reactiveVal()` objects — consolidate related reactive state into one `reactiveValues` container. When mutable cross-module state is needed (e.g. the active client/chat for model switching), add a slot to the shared `reactiveValues`, not a standalone `reactiveVal`.

**Shiny promise-in-observer rule (CRITICAL):** Never let a `promise(...)` call be the **last expression** in an `observeEvent` / `observe` body. If it is, Shiny treats the observer as an *async observer* and holds the reactive flush open until the promise settles — so any UI invalidations triggered inside the observer (e.g. writing `state$pending_approval`) are never flushed to the browser until the promise resolves. For "pause and wait for user interaction" patterns:
```r
# WRONG — flush stalls, UI never updates until promise resolves
observeEvent(input$btn, {
  promise(function(resolve, reject) { state$pending <- list(resolve = resolve) })
})

# CORRECT — assign to throwaway var, end with invisible(NULL)
observeEvent(input$btn, {
  .pr <- promise(function(resolve, reject) { state$pending <- list(resolve = resolve) })
  invisible(NULL)   # observer completes synchronously; UI flushes immediately
})
```
The `resolve` function stored in `state$pending` is called later from an Allow/Deny observer (which has the correct reactive domain). Never use `later::run_now()` to "pump" the event loop inside a Shiny observer — the reactive graph is non-reentrant and will block. Never use `promises::then()` for UI updates in Shiny — `then()` callbacks run in the `later` queue with NULL reactive domain and cannot write to `reactiveValues`.

**Shiny async tool approval pattern:** For approval/question bars (tool gate UI in Shiny), use `chat_ui(footer = tagList(uiOutput("ca_approval_ui"), uiOutput("ca_question_ui")))` — the `footer=` slot is rendered above the input box. Bars use `border-top` only (no coloured backgrounds). Reference implementation: `inst/examples/test_shiny_ask_fn.R`.

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
codeagent_app(client, theme="default") # Shiny UI
```

### Subsystems

**`query.R`** — `codeagent_client()` is the primary factory; builds `CodagentClient` S3 object. `codeagent()` dispatches new/legacy style. `agent_loop()` is called per-turn (was `query_loop`). `.register_all_tools()` wires all tool groups. `.handle_agent_error()` classifies PTL/rate-limit/network/auth errors with backoff. `verify_r_tests()` is a built-in verify function.

**`permissions.R`** — **Seven-mode** gate: `default / plan / accept_edits / bypass / dont_ask / auto / bubble`. `bubble` returns `"ask"` to bubble permission up to parent agent (sub-agent mode). `auto` uses haiku ML classifier. `DenialTracker` emits warnings.

**`hooks.R`** — `HookRegistry` with **12 lifecycle events** via `HookEvent$*`: tool events (`PreToolUse`, `PostToolUse`, `PostToolUseFailure`), permission events (`PermissionDenied`, `PermissionRequest`), message events (`UserMessage`, `AssistantMessage`), and lifecycle events (`SessionStart`, `Stop`, `PreCompact`, `SubagentStart`, `SubagentStop`). Mount points: `agent_loop` fires SessionStart(iter 1)/Stop(all terminal returns)/PreCompact(before maybe_compact); `agent_tool` fallback fires SubagentStart/Stop. Legacy `register_pre()`/`register_post()` still work.

**`tools_builtin.R`** — 8 core tools (Bash, Read, Write, Edit, MultiEdit, Glob, Grep, LS). All return `ContentToolResult` with `extra$display` (HTML title + markdown) for shinychat tool cards. All have `_intent` parameter for card display.

**`tools_r.R`** — Wraps `btw::btw_tools()`. `.BTW_GROUPS` covers all 10 btw 1.2.1 groups: `agent, cran, docs, env, files, git, ide, pkg, sessioninfo, web`. `btw_tool_skill` excluded (handled by skill system).

**`tool_run_r.R`** — `run_r_tool()` wraps `btw::btw_tool_run_r()` (arbitrary R execution, no sandbox) behind the **permission gate** under tool name `"RunR"`. `destructive_hint=TRUE`, never read-only → `default` mode resolves to `"ask"` (user confirms each call), `plan`/`dont_ask` → `deny`, `bypass` → allow. btw excludes `btw_tool_run_r` from default `btw_tools()`, so the gated wrapper is the only execution path. `.runr_to_tool_result()` is a special case of the `tool_display.R` adapter.

**`tool_display.R`** — **typed tool-card contract + render dispatcher**. `extra$display$toolcard = {kind, status, icon, title, payload}` (private nested key (`toolcard`), never collides with shinychat's reserved display keys). `kind ∈ {code, image, table, diff, text, error}`. `.tool_result2()` builds it and renders the rich card ONCE into BOTH `display$html` (in-chat bubble, rendered natively by shinychat inside `<shiny-tool-result>`, `full_screen=TRUE` + `open=FALSE` = collapsed/expandable) AND `display$right_output` (right Output panel). `render_tool_output(display)` is the dispatcher (code→Prism-highlighted+copy, image→zoomable img+toolbar, table→reactable, diff→base-R-LCS colored, error→styled box). `.adapt_tool_result(result)` is the **universal adapter** called at the `server_chat.R` `on_tool_result` boundary — normalizes ANY native `ContentToolResult` (raw `btw::btw_tools()`, web, skills) into the typed contract, idempotent. The 8 builtins + RunR use `.tool_result2()`; everything else gets typed by the adapter. Interactivity (copy/zoom/fullscreen/download) is document-delegated JS in `agent.js`; CSS classes `.toolcard-*` in `styles.css`; Prism.js via CDN in `head_assets()`.

**`tools_agent.R`** — `agent_tool()` uses `btw_tool_agent_subagent` when btw available; falls back to codeagent's own loop. Supports `worktree_isolation=TRUE` (git worktree per sub-agent). Discovers custom agents from `.btw/agent-*.md`, `.claude/agents/`. `codeagent_mcp_server()` wraps `btw::btw_mcp_server()`. `install_codeagent_cli()` installs Rapp-based CLI.

**`mcp_client.R`** — **MCP client (M8)**. `register_mcp_client(chat, config)` wraps `mcptools::mcp_tools()` to connect EXTERNAL MCP servers (stdio transport via processx child process) and register their tools onto the Chat. Config = JSON path or inline list (`mcpServers: {name: {command, args, env}}`). `codeagent_client(mcp_config=)` opts in. Complements `codeagent_mcp_server()` (server side). Graceful: missing mcptools/bad config → 0 tools, no crash. Sandbox (fs/network isolation) NOT implemented — see `references/sandbox-limitations.md` (権限门控 + Hook 策略 is the security model; OS/container sandbox is host-layer responsibility).

**`compaction.R`** — **Five-level** compaction:
- L1 `snip_old_tools`: replace large old tool results with placeholder
- L2 `session_memory_compact`: summarise early turns via compact model
- L3 `full_compact`: fork agent → 9-section `<summary>`
- L4 `ptl_fallback`: drop oldest turns on 413 errors
- L5 `context_collapse`: read-time projection (truncate all tool result values)

> **Current flow (task 01 alignment):** the live `maybe_compact()` trigger is now
> **two-level** — `snip_old_tools` pre-step → `session_memory_compact` → fall back to
> `full_compact` (verbatim 9-section prompt). `ptl_fallback`/`context_collapse` remain
> as reactive/utility paths. Dynamic per-model window lives in `R/context.R`.
> **Known gap (partly closed):** turn-boundary compaction runs before each
> `chat$chat()`. Between tool rounds *within* a turn, an **opt-in** mid-loop snip
> (`register_midloop_compaction()` via ellmer's released `on_tool_result`) clears
> old tool results when over threshold — enable with `settings$midloop_compact`
> or `options(codeagent.midloop_compact = TRUE)`. The cleaner target is upstream
> `on_turn_start` (PR tidyverse/ellmer#1052); see
> `references/plan/13-mid-loop-compaction.md`.

**`tools_web.R`** — `web_fetch_tool()` and `web_search_tool()`. All tools return `ContentToolResult` with `extra$display` (HTML title + markdown preview for humans). WebSearch backend: `BRAVE_API_KEY` → Brave Search API (real results, 2000 free/month); fallback → DuckDuckGo Instant Answer (entity queries only, no key needed). WebFetch uses httr2 directly (no Chrome dependency). btw `web_read_url` (needs Chrome) is available as extra via `btw_groups = "web"`.

**`skills.R`** — **btw-compatible** skill system. Skill format: `<name>/SKILL.md` directories (not flat `.md` files). Uses `btw:::btw_skills_list()` as primary discovery backend. Discovery paths: codeagent `inst/skills/` + btw paths + `.btw/skills/` + `.agents/skills/` + `.claude/skills/` + `.codex/skills/`. `.make_skill_tool()` registers `use_skill` ellmer tool for LLM semantic auto-trigger; returns `ContentToolResult` with HTML title card. Two trigger paths: user `/name` → `load_skill_prompt()` inject; LLM semantic match → `use_skill` tool call. User custom skills: use `~/.btw/skills/` (not `~/.codeagent/skills/`).

**`client_config.R`** — `codeagent_client_config(alias=)` reads `codeagent.md` / `.codeagent/config.md`. Supports single client spec (`"openai/model"`) or alias maps with interactive selection. `use_codeagent_md()` creates template.

**`memory.R`** — **auto-memory (M6)**. Persistent agent memory under `~/.codeagent/memory/<slug>.md` (YAML front-matter `name`/`description` + body) + `MEMORY.md` index. `write_memory/list_memories/recall_memories/delete_memory`. The `remember` tool (`register_memory_tool`) lets the LLM persist durable facts; `recall_memories()` is injected into `.build_system_reminder` on iteration 1 (not every turn — model retains it after). Survives across sessions.

**`model_switch.R`** — **lossless model switch (M1)**. `switch_model(client, model)`: Route A swaps ellmer R6 `private$provider` in place (same Chat object → callbacks/stream_controller/closures untouched); Route B (tryCatch fallback) rebuilds via public API. `.resolve_model_chat` reuses `client_config` alias resolution. Shiny uses `.swap_provider` directly (Route A only, to keep Chat identity); CLI uses full `switch_model`. See `references/model-switch-alternatives.md`.

**`settings.R`** — Priority: env vars > `~/.codeagent/settings.json` > `.codeagent/settings.json` > defaults. `.build_system_reminder()` injects ephemeral per-turn context (date/iteration/cwd) into user message (not system prompt) to preserve prompt cache.

**`compaction.R` `.make_compact_chat()`** — When `CODEAGENT_BASE_URL` set, uses `chat_openai_compatible` with `databricks-claude-haiku-4-5`; otherwise `chat_anthropic`.

**`ui.R`** — `codeagent_app(client, pinned_skills, theme, port, launch.browser)`. Three accordion panels: Sessions (1st, open), Skills (2nd, searchable + scrollable + install), Settings (permission mode + btw tool groups + theme toggle). Themes: `"default"` (pure bslib), `"flatly"` (Bootswatch), `"darkly"` (Bootswatch), `"glass"` (custom visual layer). Tools stream via `stream="content"` → shinychat renders tool cards automatically.

**`sessions.R / mutations.R`** — Sessions stored as JSONL under `~/.codeagent/projects/<hash>/`. Session titles fall back to first user message (not UUID). `fork_session()` implemented. **Lossless persistence (M7)**: `save_session` writes a `chat-state` line (`contents_record` → gzip → base64, JSON-safe) preserving tool requests/results; per-message text lines remain for UI display + legacy fallback. `restore_session_into_chat(chat, session_id, cwd)` prefers the lossless state (tool calls intact), falls back to text turns for pre-M7 sessions. `session_id = NULL` → continue most recent (CLI `--continue`). Shiny session-load + CLI `--continue`/`--resume` both use it.

### Key design decisions

- **`codeagent_client()` is the central factory**: takes any ellmer Chat, injects tools + system prompt, returns `CodagentClient`. Both `codeagent()` and `codeagent_app()` accept `CodagentClient` as first arg; old flat params still work for backward compat.
- **All tools return `ContentToolResult` with `extra$display`**: `title` (HTML, use `htmltools::HTML()`), `markdown` (human-readable preview), `value` (LLM-facing text). See `ellmer-tool-calling.md` for the full `extra$display` field spec.
- **WebSearch backends**: `BRAVE_API_KEY` env var enables Brave Search API; without it falls back to DuckDuckGo (entity queries only). Never rely on DDG for general questions.
- **btw as tool layer**: codeagent is the harness (loop/permissions/compaction/hooks/skills); btw provides the R-environment tool set (docs/git/pkg/env/etc). They compose, not compete.
- **Skill format is `name/SKILL.md`** (btw/Claude Code compatible). Never use flat `.md` files.
- **`ContentToolResult` with `extra$display`**: all tools return typed results with HTML title + markdown for shinychat cards.
- **S7 slot access is fragile**: wrap in `tryCatch`.
- **`%||%` null-coalescing**: defined in `utils.R`.
- **shinyAssistantUI canonical groups**: when mimicking the slash menu, use the 6 fixed sections from `shinyAssistantUI` examples/source — `Context`, `Model`, `Customize`, `Slash Commands`, `Settings`, `Support`. Do not invent ad-hoc group names for the UI prototype unless the user explicitly asks.

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
- ✅ 12-event hook system (`HookEvent$*`) — tool/permission/message/lifecycle
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
- ✅ Rapp CLI (`exec/codeagent.R`) — `run`(--model/--continue/--resume/--stream) + `chat`/`repl`(交互式 REPL：readline loop + /model//compact//clear//help 斜杠命令 + 流式) + app/skills/mcp/info
- ✅ MCP server (`codeagent_mcp_server()`) + MCP client (`register_mcp_client()`, stdio)

---

## Backlog（后续计划）

对标 Claude Code 的已知缺口，按价值排序。实现前先确认上游（ellmer/btw/shinychat）是否已有原生支持。

### P1 — Shiny ask_fn（工具审批 UI）

**现状**：CLI REPL 有 `.console_ask_fn`（`readline()` 阻塞等待）；Shiny app 的 `ask_fn = NULL`（默认模式下写操作无交互审批）。

**目标**：`default` 权限模式下，Shiny app 对"需要确认"的工具请求弹出审批 UI，用户点 Allow/Deny，结果异步返回给权限门。

**实现思路**（参考 `/usrfiles/shared-projects/users/kaiping_yang/ClaudeAgentSDK/examples/16_shinychat_tool_approval_inline.R` 的 UI 设计，但底层机制完全不同）：
```r
# R/server_chat.R 里构造 Shiny ask_fn，注入 codeagent_client()
.shiny_ask_fn <- function(session, state) {
  function(tool_name, tool_input) {
    # 通过 promise + reactiveVal 实现异步等待
    # 1. state$pending_approval <- list(tool_name, tool_input, resolve_fn)
    # 2. renderUI approval bar → Allow/Deny buttons
    # 3. observeEvent(input$tool_allow) → resolve_fn(TRUE)
    # 4. observeEvent(input$tool_deny)  → resolve_fn(FALSE)
    # 返回 TRUE/FALSE 给 .make_permission_checker
  }
}
```

难点：`ask_fn` 目前是同步回调，Shiny 需要异步等待用户点击。需要用 `promises`/`coro::async` 桥接，或改 `ask_fn` 接口为 promise-returning。

### P2 — AskUserQuestion 工具

Claude Code 的 `AskUserQuestionTool`：agent 在 loop 中途主动暂停并问用户问题，用户回答后 loop 继续。

**与 ask_fn 的区别**：ask_fn 是权限门（"能不能执行这个工具"），AskUserQuestion 是信息采集（"我需要更多信息才能继续"）。

```r
# R/tools_ask_user.R
ask_user_tool <- function(session = NULL) {
  ellmer::tool(
    name = "AskUserQuestion",
    fun = function(question, choices = NULL) {
      # CLI: readline(question)
      # Shiny: showModal + reactiveVal + promise
    },
    description = "Ask the user a clarifying question and wait for their answer before continuing.",
    arguments = list(
      question = ellmer::type_string("The question to ask the user."),
      choices  = ellmer::type_array("Optional choices.", items = ellmer::type_string(), required = FALSE)
    ),
    annotations = ellmer::tool_annotations(title = "AskUserQuestion", read_only_hint = TRUE)
  )
}
```

### P3 — 工具并发执行

Claude Code 的 `StreamingToolExecutor` 区分 read-only 工具（并发）和写操作（串行）。当前 ellmer 串行执行所有工具。

**依赖上游**：ellmer 是否支持并发工具执行。关注 ellmer 进展，有原生支持时直接受益，不自己实现。

### P4 — `@path` import in CLAUDE.md

Claude Code 支持 CLAUDE.md 中用 `@/path/to/file.md` 内联引用外部文件。当前 `.load_claude_md()` 不解析 `@` 引用。

**实现**：在 `.load_claude_md()` 读取每个文件后，正则扫描 `^@(.+)` 行，递归读取引用文件并替换。注意循环引用保护（`seen` set 已有，复用即可）。

### P5 — Dollar budget（成本控制）

Claude Code 有 `maxBudgetUsd`，按 API 成本限制。当前只有 token budget。

**低优先级**：需维护各 provider 的 token 价格表，维护成本高。等有明确需求再做。

### 语音输入

**等上游**：JamesHWade 的 shinychat `feature/audio-input` 分支（`audio_input="transcribe"` 参数）完成后，codeagent 只需在 `ui_panels.R` 加一个参数。不自己实现。进展跟踪：https://github.com/posit-dev/shinychat/issues/146
