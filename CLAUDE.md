# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

`codeagent` is an R package — an R-native implementation of Claude Code CLI capabilities (harness layer), built on `ellmer` + `btw`. It does **not** wrap the Claude Code CLI subprocess; it reimplements the agent loop, tools, permissions, compaction, skill system, and Shiny UI from scratch.

**Reference docs:** `.claude/docs/` contains learning materials. Read before touching a subsystem.

| File | When to read |
|------|-------------|
| `ellmer-package.md` | Core Chat API, tool(), type_*(), ContentToolResult, S7 internals |
| `ellmer-tool-calling.md` | tool(), type_*(), `ContentToolResult` `extra$codeagent$artifact` / `extra$display`, tool_annotations(), on_tool_request/result, stream="content" |
| `btw-package.md` | btw 1.2.1 overview, client config, skill system |
| `btw-tools.md` | btw 工具组完整参考（10组 + skill系统 + btw_app设计）|
| `shinychat.md` | chat_append(), tool cards, _intent display, `ContentToolResult` `extra$display` |
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

**内部模型名同视为敏感标识（token 是绝对底线，模型名/endpoint 次之但仍规避）：** 公司内部模型代号
（私有 serving-endpoint 名，非公开 OpenAI/Anthropic 模型名）**不得**硬编码进被 git 跟踪的文件或 commit message。
example/demo/测试里模型一律 `Sys.getenv("CODEAGENT_MODEL", "<通用占位>")`，默认值用通用公开名
（`gpt-4.1`/`gpt-4o-mini`），绝不写真实内部代号。commit message 也不提内部模型名。
运行时产物 `.shinychat/` 会话记录会记真实 model 名——保持 git/Rbuild 忽略，别提交。
**注**：token 全历史零泄露是硬底线；模型名/endpoint 若历史已泄（当前 HEAD 已清）可接受不改历史，往后规避即可。

**知识产权铁律 — 对齐是"对标公开接口/行为"，绝不是"复刻源码"：** codeagent 的设计参考对象是
Claude Code 和 Claude Agent SDK，对齐**只**针对它们的**公开接口 / 公开文档 / 公开可观察行为**
（如 hook 事件名 `UserPromptSubmit`/`PreToolUse`、公开字段契约 `block`/`additionalContext`、SDK
`__init__.py` 导出的公开类型）——这些是官方要求用户在配置里书写的接口契约，复刻接口名/契约不构成侵权
（接口对标，非实现照搬）。**绝不**在代码、注释、commit message、plan、对话、文档里出现"读/复刻/移植
Claude Code **源码**"、"反编译/逆向"、"基于源码学习/确认其实现"这类措辞——即使实际只是学习公开行为，
这类字面也有被解读为"照搬源码"的风险。commit message 与文档一律写"**对标 Claude Code / Claude Agent
SDK 公开 hooks 接口 / 公开行为**"，不写"源码"。历史遗留的风险措辞发现即修（如需改历史 commit message，
留备份分支后 rebase reword，本条已于 2026-08-07 清理一例）。

**命名双向对齐 CC + Claude Agent SDK（含历史漂移备案）：** 本项目最早复刻时**先参考 Claude Agent SDK、
后参考 Claude Code**，故部分历史命名源自 SDK 而非 CC，可能与 CC 现行事件名不完全一致：
- `UserMessage`（旧）= CC 公开事件 `UserPromptSubmit`（对齐后应逐步统一到 CC 名）。
- `AssistantMessage`：**与 Claude Agent SDK 的公开类型 `AssistantMessage` 同名但语义漂移**——SDK 里它是
  一个**消息类型**（`Message` 家族），codeagent 里却把它当成一个 **hook 事件**用；CC 的 `HOOK_EVENTS`
  里**没有**这个事件（"模型输出后"CC 用 `Stop` + `last_assistant_message` 字段表达）。因有下游消费方
  （`ui_customizations.R`），暂保留不废弃，挂 TODO 待未来评估合并进 `Stop`。
- 新增/改名 hook 事件时，优先对齐 CC 公开事件名；若 CC 无对应而 SDK 有，注明来源与语义层级（事件 vs 消息类型），
  避免再次同名漂移。

**每次改完代码必须重装包并更新 codegraph：**
```r
pak::local_install(".", ask = FALSE, upgrade = FALSE)
```
```bash
codegraph sync   # 更新符号索引，让 kiro/AI 工具看到最新代码
```
这确保 `codeagent chat` / `codeagent_app()` 等用安装版运行的入口点使用最新代码。`devtools::load_all()` 只在当前 R session 里生效，launcher（`--vanilla`）和 CLI 用的是已装的包。codegraph 不会自动同步，手动 sync 后 kiro 的 codegraph 审核才能看到新符号。

> **测试无误 = 要装到本地才算数。** 每次改完代码、跑完测试后，务必 `pak::local_install(".", ask = FALSE, upgrade = FALSE)` 把**当前版本装到本地**——`load_all()` 只在当前 session 生效，真实验证/CLI/launcher 跑的是已安装的包。

**新增功能必须同步更新 README.md：**
- 新导出函数/新 feature → 在 README 对应 section 补一行
- 重要行为变更 → 更新 README 相应描述
- README 79 commits 不更新已是教训：每次 commit 前检查 README 是否需要同步

**改代码必须同步更新测试和 example：**
- 新增/修改函数 → 对应 `tests/testthat/test-*.R` 补测试
- 修改公开 API（签名/行为）→ 对应 `inst/examples/demo_*.R` 或 `test_databricks.R` 更新
- 新功能 → 加进 `inst/examples/test_databricks.R` 的 section
- **新增任何导出函数，必须同时：① 确认是否需接入 `.register_all_tools()`/调用链；② 同步写 `test-*.R` 覆盖主路径和降级路径；③ 加进 `_pkgdown.yml` 的 reference 索引（对应 section 补一行）——否则 pkgdown CI 报 `topic missing from index` 挂掉（血泪：`data_shield_ocr_scanner` 漏加致 pkgdown build 失败）。改完跑 `pkgdown::check_pkgdown()` 应 `No problems found`。**

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

**codeagent 0.2.0 shared release 基线（2026-08-20）：**

共享发布库：`/usrfiles/shared-projects/users/kaiping_yang/Rlibs/codeagent/R-4.4`。发布与E2E必须让该库先于公共site library。

- `codeagent` 0.2.0（`main@509835f` / tag `v0.2.0`）
- `ellmer` 0.4.2.9000 @ `19be478ebf1a2e5d2db96a8aeaca71592c8d3f26`
- `btw` 1.4.0.9000 @ `d11591b09d9127b05d673e8c96569d2bbae2ec44`
- `shinychat` 0.4.0.9000 @ `c1654aa2e13c979e52a16edace094d30680fa4dd`（monorepo；安装源为 `posit-dev/shinychat/pkg-r`）
- `shiny` 1.14.0（shared stable）
- `bslib` 0.11.0（shared stable）
- `mcptools` >= 1.0.2.9000（所有 MCP client/server 入口的最低安全版本）
- `httr2` 1.3.0（保持稳定版）

**当前个人默认开发环境（2026-08-31）：**

个人库：`/home/kaiping.yang/R/x86_64-pc-linux-gnu-library/4.4`。

- `ellmer` 0.4.2.9000 @ `a64f94e644718c0598b01b0cd50a3c21c2646435`
- `btw` 1.4.0.9000 @ `d11591b09d9127b05d673e8c96569d2bbae2ec44`
- `shinychat` 0.4.0.9000 @ `2b249764ce45b224224b7d185b3f34f14d0ad84f`（monorepo：`posit-dev/shinychat/pkg-r`）
- `shiny` 1.14.0.9000 @ `81844600fc15f1952838546faa6699d0506ce7f9`
- `bslib` 0.12.0.9000 @ `6935d9819fcb37e0b42ffa54f4e1cab0418ec2ce`
- `mcptools` 1.0.2.9000 @ `079e011e6f2a515565f903dc8a5b7c4d793746f1`
- `Rapp` 0.4.1.9000 @ `489655f24945042791ddb083d0d5518c4a905d9f`
- `httr2` 1.3.0.9000 @ `7ce699f813e662850ea21d9f87e242e0c699f9fe`

普通R环境直接使用该个人库，不依赖`/tmp` candidate或硬编码`.libPaths()`。
上方0.2.0 shared release保持不变，除非另行执行发布promote。当前工作树
`DESCRIPTION`固定全部八个完整SHA；更换任一SHA后必须同步manifest并重新执行
完整testthat、R CMD check以及classic/page_chat真实Chromium gate。

开发版 `Version` 字符串不能唯一标识构建，必须同时核对完整 `RemoteSha`。
价格数据不在启动或模型请求时自动联网刷新。需要时由用户显式调用：

```r
price_update <- update_model_prices()
price_update$message
```

该调用只刷新 ellmer 的公开价格快照；网络失败保留现有 cache，custom/private endpoint 更新后仍可能无价格。


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

**`mirai::mirai_map()` 常量必须走 `.args`，不能用 `...`：** mirai (>= 2.x，验证于 2.7.1)
**不会**把 `...` 里的具名参数绑定到 worker 进程 —— worker 里那些参数是 missing，函数报
`argument "x" is missing, with no default`，mirai 返回 `miraiError` 对象而非你的返回值。
正确写法：`mirai_map(items, fn, .args = list(k1 = v1, k2 = v2))`（`.args` 绑定 + 保序）。
另注意 `is.character()` 对 `miraiError` 返回 **TRUE**，判定 worker 是否失败要用
`inherits(x, "miraiError")` 而非字符串检查。参考 `R/team.R` `team_run()` 与
`R/team_board.R` `team_coordinate()` 的 worker_loop（两处都用 `.args`）。worker 闭包若引用
包内部函数（非导出），把函数的 `environment()` 设成 `asNamespace("codeagent")` 即可解析。

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
              → central gate on `on_tool_request`  # .install_permission_gate:
                  → HookRegistry$run_pre()          #   PreToolUse
                  → .gate_decide(): settings$tools overrides > capabilities >
                    check_permission()              #   7-mode gate; deny -> tool_reject
                  → HookRegistry$run_permission_denied() on deny
              → tool execution (built mode="bypass"; gate is sole authority)
              → HookRegistry$run_post() on `on_tool_result`  # PostToolUse
      → verify_fn (optional)    # re-enter if fails
      → HookRegistry$run_assistant_message()
      → save_session()
```

> **Tool permissions = one central gate** (`R/tools_gate.R`, `.install_permission_gate`).
> All tools (native + btw + Format + MCP) are built ungated (`mode="bypass"`) and
> governed uniformly by ellmer's rejectable `on_tool_request` (sync) /
> `maybe_on_tool_request_async` (Shiny). Fine-grained control via `settings$tools`
> (`sets`/`capabilities`/`overrides`); see README → Tool permission control.

### Client object model

```r
# Step 1: any ellmer Chat (user picks backend)
chat <- ellmer::chat_openai_compatible(...)   # Databricks/Azure
# OR chat <- ellmer::chat_anthropic(...)
# OR chat <- ellmer::chat_ollama(...)

# Step 2: codeagent_client() injects tools + system prompt → CodeagentClient
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

**`query.R`** — `codeagent_client()` is the primary factory; builds `CodeagentClient` S3 object. `codeagent()` dispatches new/legacy style. `agent_loop()` is called per-turn (was `query_loop`). `.register_all_tools()` wires all tool groups. `.handle_agent_error()` classifies PTL/rate-limit/network/auth errors with backoff. `verify_r_tests()` is a built-in verify function.

**`permissions.R`** — **Seven-mode** gate: `default / plan / accept_edits / bypass / dont_ask / auto / bubble`. `bubble` returns `"ask"` to bubble permission up to parent agent (sub-agent mode). `auto` uses haiku ML classifier. `DenialTracker` emits warnings.

**`hooks.R`** — `HookRegistry` with **12 lifecycle events** via `HookEvent$*`: tool events (`PreToolUse`, `PostToolUse`, `PostToolUseFailure`), permission events (`PermissionDenied`, `PermissionRequest`), message events (`UserMessage`, `AssistantMessage`), and lifecycle events (`SessionStart`, `Stop`, `PreCompact`, `SubagentStart`, `SubagentStop`). Mount points: `agent_loop` fires SessionStart(iter 1)/Stop(all terminal returns)/PreCompact(before maybe_compact); `agent_tool` fallback fires SubagentStart/Stop. Legacy `register_pre()`/`register_post()` still work.

**`tools_builtin.R`** — 8 core tools (Bash, Read, Write, Edit, MultiEdit, Glob, Grep, LS). All return `ContentToolResult` with `extra$display` (HTML title + markdown) for shinychat tool cards. All have `_intent` parameter for card display.

**`tools_r.R`** — Wraps `btw::btw_tools()` with explicit ownership. Full-client/UI registration filters raw `btw_tool_agent_*`; the dedicated Agent owner selects exactly one foreground implementation (shield/async/worktree → codeagent Agent, plain sync → upstream agent). Runtime btw-group changes build a target snapshot and call `set_tools()` atomically, preserving core/MCP/skill/file-owner tools; failures restore the old snapshot and wrappers. `btw_tool_skill` remains owned by the skill system.

**`tool_run_r.R`** — `run_r_tool()` wraps `btw::btw_tool_run_r()` (arbitrary R execution, no sandbox) behind the **permission gate** under tool name `"RunR"`. `destructive_hint=TRUE`, never read-only → `default` mode resolves to `"ask"` (user confirms each call), `plan`/`dont_ask` → `deny`, `bypass` → allow. btw excludes `btw_tool_run_r` from default `btw_tools()`, so the gated wrapper is the only execution path. `.runr_to_tool_result()` is a special case of the `tool_display.R` adapter.

**`tool_display.R`** — **versioned cross-UI artifact contract + official shinychat adapter**. The primary UI-neutral source is `extra$codeagent$artifact = {schema="codeagent.tool-artifact",version=1,kind,status,icon,title,payload}` (web provenance remains in `extra$codeagent$sources`). Public `tool_result_artifact()` and `tool_result_value()` let any UI consume supported artifacts and fall back to model-safe text; `codeagent_stream_async(on_tool_result=)` exposes both plus the optional shinychat `display`. `.artifact_tool_result()` projects artifacts through `shinychat::tool_result_display()`; rich artifacts request official `open_style = "framed"`. `.tool_result2()` is compatibility-only and no longer defines a second protocol. The right panel renders on demand from the artifact, so no `right_output` duplicate is stored. `.adapt_tool_result()` upgrades unversioned/legacy artifacts to v1, preserves future versions, normalizes native/btw/MCP results without dropping `request`, and keeps replay migration presentation-only.

**`tools_agent.R`** — Dedicated Agent ownership prevents duplicate foreground subagent tools. Shielded foreground subagents inherit the same live `DataShield`, gate the reply before hooks/callbacks/parent results, and do not persist raw sidechains; shielded background agents fail closed. `codeagent_mcp_server(..., session_tools=FALSE)` calls `mcptools::mcp_server()` directly, requires mcptools >= 1.0.2.9000, and rejects session tools on non-loopback HTTP because those controls bypass the Chat permission gate/Data Shield.

**`mcp_client.R`** — External MCP registration and generated server subprocesses enforce mcptools >= 1.0.2.9000. An old client warns and registers zero tools; an old server stops. stdio and loopback HTTP keep `session_tools=FALSE` unless explicitly enabled. Config remains a JSON path or inline `mcpServers` list; OS/container sandboxing is still host responsibility.

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
> **Known gap (mostly closed):** turn-boundary compaction runs before each
> `chat$chat()`. Between tool rounds, `register_midloop_compaction()` (ellmer's
> released `on_tool_result`) compacts in two tiers mirroring CC
> `autoCompactIfNeeded`: a **budget-aware micro snip** ON by default
> (`settings$midloop_compact`) and an **opt-in full two-level compact**
> (`settings$midloop_full_compact`) via `CompactionController$compact_now()`.
> Remaining gap is *timing*: `on_tool_result` only fires between tool rounds, not
> before every request. `on_tool_request` cannot substitute (it fires after the
> request, inside `invoke_tools`, per tool). True parity needs upstream
> `on_turn_start` (PR tidyverse/ellmer#1052); see
> `references/plan/13-mid-loop-compaction.md`.
>
> Token accounting is deliberately zero-implicit-network: `token_count_with_estimation(chat,
> allow_network=FALSE)` includes `cached_input` from the last usage and otherwise uses the
> heuristic. Compaction, context-left, teardown and Shiny never call remote token counting;
> only an explicit future action may pass `allow_network=TRUE`.

**`tools_web.R` / `web_citations.R`** — WebSearch/WebFetch return legal `ContentToolResult`s plus validated source records in `extra$codeagent$sources`. Citation mode is opt-in (`"off" | "shiny_aside"`) and buffers the final answer. Custom tools use model markers (`[[cite:SOURCE_ID|visible claim]]`); ellmer provider-native `ContentCitation` / `WebSource` objects are converted to opaque server-owned refs whose grounded spans never enter marker syntax. Both paths accept only current-turn registry entries, scan claim/grounded span/title/quote/URL, escape untrusted values, revalidate URLs, and rebuild the same fixed `<shiny-aside>` allowlist before the browser sees anything. Replay rebuilds from the lossless original turn rather than trusting shinychat-generated provider markup. Web fetches allow only public http/https, reject userinfo/private/reserved/mixed DNS, re-authorize every redirect, and pin the validated address with curl resolve to prevent DNS rebinding.

**`skills.R`** — **btw-compatible** skill system. Skill format: `<name>/SKILL.md` directories (not flat `.md` files). Uses `btw:::btw_skills_list()` as primary discovery backend. Discovery paths: codeagent `inst/skills/` + btw paths + `.btw/skills/` + `.agents/skills/` + `.claude/skills/` + `.codex/skills/`. `.make_skill_tool()` registers `use_skill` ellmer tool for LLM semantic auto-trigger; returns `ContentToolResult` with HTML title card. **Metadata cache (2-tier):** `list_skills_meta()` caches parsed metadata in-memory AND on disk (`.skill_cache_read/_write` under `<config>/cache/skills/`, keyed by cwd + a `SKILL.md` mtime/count signature `.skill_dirs_mtime_sig`). A disk hit returns *before* `btw:::btw_skills_list()` runs, so a fresh process skips the slow scan; atomic temp+rename writes, best-effort I/O (corrupt/missing cache → full rescan). Two trigger paths: user `/name` → `load_skill_prompt()` inject; LLM semantic match → `use_skill` tool call. User custom skills: use `~/.btw/skills/` (not `~/.codeagent/skills/`).

**`client_config.R`** — `codeagent_client_config(alias=)` reads `codeagent.md` / `.codeagent/config.md`. Supports single client spec (`"openai/model"`) or alias maps with interactive selection. `use_codeagent_md()` creates template.

**`memory.R`** — **auto-memory (M6)**. Persistent agent memory under `~/.codeagent/memory/<slug>.md` (YAML front-matter `name`/`description` + body) + `MEMORY.md` index. `write_memory/list_memories/recall_memories/delete_memory`. The `remember` tool (`register_memory_tool`) lets the LLM persist durable facts; `recall_memories()` is injected into `.build_system_reminder` on iteration 1 (not every turn — model retains it after). Survives across sessions.

**`model_switch.R`** — **verified lossless model switch**. Route A is strictly name-only: provider configuration and Model params/extra_args must be unchanged, then public `set_model()` is verified and rolled back on failure. Provider/endpoint/credentials/API-arg changes use Route B, which rebuilds a client while preserving history, tools, hooks, budgets, MCP settings and the same live Data Shield. Shiny keeps its captured Chat identity and therefore rejects Route-B targets with guidance to start a new session/app; picker, `/model`, and modal share this rule and reject changes while streaming. Direct private provider replacement is forbidden because it caused Provider/Model split-brain.

**`settings.R`** — Priority: env vars > `~/.codeagent/settings.json` > `.codeagent/settings.json` > defaults. `.build_system_reminder()` injects ephemeral per-turn context (date/iteration/cwd) into user message (not system prompt) to preserve prompt cache.

**`query.R` / `stream.R` / `server_chat.R`** — All terminal paths use the pure `.map_finish_reason()` mapping. Fixed order is final response/retry → map raw finish reason → append static note → output gate → visible callback/AssistantMessage hook → save → Stop hook. Sync, stream and Shiny therefore agree on completed/truncated/filtered/incomplete-tool-use semantics while retaining the raw provider reason.

**`compaction.R` `.make_compact_chat()`** — When `CODEAGENT_BASE_URL` set, uses `chat_openai_compatible` with the configured compact model; otherwise `chat_anthropic`.

**`ui.R`** — `codeagent_app()` keeps instant startup: tool/skill registration is deferred behind the initialization overlay, and input remains disabled until ready. Citation mode is explicitly opt-in and buffer-then-show; ordinary streaming is unchanged. `ui_layout="page_chat"` uses one top-level `page_chat()`/one chat root, the official `page_chat_theme()` baseline, a persistent global dark-mode + Workspace toolbar (`toolbar_input_button()`), a supported `bslib::sidebar()`, and `chat_drawer()` for the Output / Files / File artifact workspace. Its chat width is explicitly `100%` of the available main column; sidebar/drawer sizing still constrains that column. Classic retains shinychat's embedded-chat width and explicitly disables its unused native drawer/history presentation. The four official drawer server APIs are centralized in `.shinychat_drawer_action()`; tool/file events call show and the toolbar calls toggle. Files may stage the current file with `chat_attachment()` + `update_chat_user_input()`. Skill prompts are wrapped as `ContentSlashCommand` only after Data Shield and reminder injection, preserving provider text and `/skill args` replay. `chat_server()`/`chat_enable_history()` remain intentionally unregistered because codeagent owns streaming, permissions, hooks, sessions, and Data Shield. The greeting uses `chat_greeting(..., persistent=TRUE)` and resets via `chat_clear(greeting=TRUE)` before New/Delete/session restore. The three static workspace tabs remain unchanged; do not reintroduce per-file dynamic tabs. Tool-group and permission mutation are rejected while streaming and applied atomically otherwise.

**`sessions.R / mutations.R`** — Sessions remain lossless JSONL (`contents_record` → gzip → base64) with text presentation lines for UI/legacy fallback. Citation mode saves only the finalized, gated deterministic presentation text while retaining lossless tool/source metadata. Replay clones a presentation Chat, migrates legacy display only on that copy, and never changes provider-facing values, request/result IDs, turn ordering, or the original Chat. `session_id=NULL` continues the most recent session.

### Key design decisions

- **`codeagent_client()` is the central factory**: takes any ellmer Chat, injects tools + system prompt, returns `CodeagentClient`. Both `codeagent()` and `codeagent_app()` accept `CodeagentClient` as first arg; old flat params still work for backward compat.
- **Tool results use official display + private metadata**: `extra$display` is built with shinychat's official constructor/fallback fields; typed artifacts and source provenance live under `extra$codeagent`. LLM-facing `value` remains provider-safe.
- **WebSearch backends**: `BRAVE_API_KEY` env var enables Brave Search API; without it falls back to DuckDuckGo (entity queries only). Never rely on DDG for general questions.
- **btw as tool layer**: codeagent is the harness (loop/permissions/compaction/hooks/skills); btw provides the R-environment tool set (docs/git/pkg/env/etc). They compose, not compete.
- **Skill format is `name/SKILL.md`** (btw/Claude Code compatible). Never use flat `.md` files.
- **Tool result normalization is explicit**: known complex results become legal `ContentToolResult`s; unknown classes deterministically error or degrade to safe text rather than relying on ellmer's deprecated complex-return coercion.
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

> **状态核对（2026-08-18）**：P4/P5 已实现，下移到"已完成"。仅语音输入待上游。

### 已完成（曾在 backlog，现已实现）

- ✅ **Shiny ask_fn 工具审批 UI**（原 P1）— `R/server_interaction.R`：`.shiny_ask_fn`（promise-returning，
  :26）+ `ask_fn` 接线（:244）+ `ca_tool_allow`/`ca_tool_deny` 按钮 + observeEvent。`ui.R:385-388` 把
  `shiny_ask_fn`/`shiny_ask_question_fn`/`egress_ask` 三条审批线全注入 session。footer inline bar 版
  （`chat_ui(footer=)`），promise + `.resolve_pending` 桥接。**三条审批线**：权限 Allow/Deny、AskUserQuestion
  问答、数据盾 egress（redact/block/raw-once）。
- ✅ **AskUserQuestion 工具**（原 P2）— `R/tools_ask_user.R`：`ask_user_tool()` + `register_ask_user_tool()`
  （query.R:705 注册）。CLI 走 `readline`/test 覆盖，Shiny 走 `.shiny_ask_question_fn` 异步 promise。
- ✅ **工具并发执行**（原 P3）— ellmer 已原生支持，codeagent `tool_mode="concurrent"` 默认透传
  `chat$stream_async(tool_mode=)`（stream.R:74/133）。并发只加速 async 工具（如子agent），同步 CLI 工具仍串行
  （ellmer 语义）。不自实现调度，直接受益上游。
- ✅ **`@path` import in CLAUDE.md**（原 P4）— `R/settings.R` `.expand_claude_md_imports()`：
  只把**整行**匹配 `^@(.+)$` 的行当作导入（正文/邮箱里的 `@` 不误伤），复用 `.load_claude_md()`
  已有的 `seen` 去重集做跨文件循环保护，另加 `max_depth`（默认 5）兜底长链。支持 `~` 展开和绝对路径；
  找不到/为空/命中循环/超深度都留 `<!-- @import ... -->` 注释说明，不静默吞掉也不报错中断。
- ✅ **Dollar budget**（原 P5）— `R/budget.R` `BudgetTracker$should_stop()` 新增 `current_cost_usd`/
  `max_budget_usd` 参数：dollar cap 独立于 token 启发式，一旦 `chat$get_cost()`（`.current_cost_usd()`
  封装）读到的花费 ≥ 上限即硬停（不等 `.BUDGET_MIN_ITERATIONS`），子agent 豁免同 token budget 一致。
  接线：`codeagent_client(max_budget_usd=)` / `CODEAGENT_MAX_BUDGET_USD` env / `settings.json`
  `max_budget_usd` 三处任一设置生效（函数参数优先，NULL 时保留已加载值）。**已知局限**：ellmer 对未注册
  价格的自定义端点（如 Databricks/Azure serving-endpoint）`get_cost()` 可能恒返回 `$0`，此时上限永不触发——
  这不是 bug，是“没有价格表就没法算钱”的固有限制。已提供显式 `update_model_prices()` 刷新 ellmer
  公开价格快照；它从不在启动或模型请求中自动调用，且 custom/private endpoint 刷新后仍可能无匹配价格。

### 语音输入

**等上游**：JamesHWade 的 shinychat `feature/audio-input` 分支（`audio_input="transcribe"` 参数）完成后，codeagent 只需在 `ui_panels.R` 加一个参数。不自己实现。进展跟踪：https://github.com/posit-dev/shinychat/issues/146
