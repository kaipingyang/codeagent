# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working
with code in this repository.

## Project

`codeagent` is an R package — an R-native implementation of Claude Code
CLI capabilities (harness layer), built on `ellmer` + `btw`. It does
**not** wrap the Claude Code CLI subprocess; it reimplements the agent
loop, tools, permissions, compaction, skill system, and Shiny UI from
scratch.

**Reference docs:** `.claude/docs/` contains learning materials. Read
before touching a subsystem.

| File | When to read |
|----|----|
| `ellmer-package.md` | Core Chat API, tool(), type\_\*(), ContentToolResult, S7 internals |
| `ellmer-tool-calling.md` | tool(), type\_\*(), ContentToolResult extra\$display, tool_annotations(), on_tool_request/result, stream="content" \| \| \`btw-package.md\` \| btw 1.2.1 overview, client config, skill system \| \| \`btw-tools.md\` \| btw 工具组完整参考（10组 + skill系统 + btw_app设计）\| \| \`shinychat.md\` \| chat_append(), tool cards, \_intent display, ContentToolResult extra\$display |
| `bslib-shinychat-layout.md` | `chat_ui(fill=TRUE)`、`page_fillable()`、`layout_sidebar()`、`sidebar(fillable=TRUE)` 的真实约束；先读再改聊天布局 |
| `bslib-toolbar-toast.md` | `toolbar()` / `toolbar_input_button()` / `toast()` 在本项目中的推荐用法 |
| `bslib-toast-vs-notification.md` | [`bslib::show_toast()`](https://rstudio.github.io/bslib/reference/show_toast.html) 与 [`shiny::showNotification()`](https://rdrr.io/pkg/shiny/man/showNotification.html) 的选型结论 |
| `shinyAssistantUI-grouping.md` | slash command / action item 的固定 6 分组：`Context` / `Model` / `Customize` / `Slash Commands` / `Settings` / `Support` |
| `btw-package.md` | btw 1.2.1 complete reference: skill system, CLI, agent tools, MCP |
| `shiny-extended-task.md` | ExtendedTask + coro::async streaming pattern used in ui.R |
| `promises-async-r.md` | promises, await(), async/await patterns in Shiny |
| `claude-code-cli-architecture.md` | Claude Code CLI design: compaction, tools, permissions, sessions |

------------------------------------------------------------------------

## Development Rules

**安全铁律 — 绝不提交/推送/打印敏感数据：** 真实 API key / token /
密码，以及具体基础设施端点 （真实
`base_url`、Databricks/serving-endpoint 主机、workspace ID/host 如
`adb-<id>.azuredatabricks.net`、 内网 hostname/IP）**绝不能**出现在被
git 跟踪的文件（源码/测试/示例/文档/模板）里。示例一律用占位符
（`YOUR-WORKSPACE.cloud.databricks.net`、`sk-...`、`<workspace-id>`），真实值只放
`.Renviron`/keyring （git 忽略）。`git add/commit/push` 前扫描
diff（`git diff --cached | grep -iE 'api[_-]?key|token|secret|sk-|ghp_|dapi|azuredatabricks\.net|serving-endpoints'`）；
打印 remote URL 时用 `sed -E 's#//[^@]*@#//***@#g'` 掩码，**绝不回显完整
token**。详见 skill `no-secrets`。

**内部模型名同视为敏感标识（token 是绝对底线，模型名/endpoint
次之但仍规避）：** 公司内部模型代号 （私有 serving-endpoint 名，非公开
OpenAI/Anthropic 模型名）**不得**硬编码进被 git 跟踪的文件或 commit
message。 example/demo/测试里模型一律
`Sys.getenv("CODEAGENT_MODEL", "<通用占位>")`，默认值用通用公开名
（`gpt-4.1`/`gpt-4o-mini`），绝不写真实内部代号。commit message
也不提内部模型名。 运行时产物 `.shinychat/` 会话记录会记真实 model
名——保持 git/Rbuild 忽略，别提交。 **注**：token
全历史零泄露是硬底线；模型名/endpoint 若历史已泄（当前 HEAD
已清）可接受不改历史，往后规避即可。

**知识产权铁律 — 对齐是”对标公开接口/行为”，绝不是”复刻源码”：**
codeagent 的设计参考对象是 Claude Code 和 Claude Agent
SDK，对齐**只**针对它们的**公开接口 / 公开文档 / 公开可观察行为** （如
hook 事件名 `UserPromptSubmit`/`PreToolUse`、公开字段契约
`block`/`additionalContext`、SDK `__init__.py`
导出的公开类型）——这些是官方要求用户在配置里书写的接口契约，复刻接口名/契约不构成侵权
（接口对标，非实现照搬）。**绝不**在代码、注释、commit
message、plan、对话、文档里出现”读/复刻/移植 Claude Code
**源码**”、“反编译/逆向”、“基于源码学习/确认其实现”这类措辞——即使实际只是学习公开行为，
这类字面也有被解读为”照搬源码”的风险。commit message 与文档一律写”**对标
Claude Code / Claude Agent SDK 公开 hooks 接口 /
公开行为**”，不写”源码”。历史遗留的风险措辞发现即修（如需改历史 commit
message， 留备份分支后 rebase reword，本条已于 2026-08-07 清理一例）。

**命名双向对齐 CC + Claude Agent SDK（含历史漂移备案）：**
本项目最早复刻时**先参考 Claude Agent SDK、 后参考 Claude
Code**，故部分历史命名源自 SDK 而非 CC，可能与 CC
现行事件名不完全一致： - `UserMessage`（旧）= CC 公开事件
`UserPromptSubmit`（对齐后应逐步统一到 CC 名）。 -
`AssistantMessage`：**与 Claude Agent SDK 的公开类型 `AssistantMessage`
同名但语义漂移**——SDK 里它是 一个**消息类型**（`Message`
家族），codeagent 里却把它当成一个 **hook 事件**用；CC 的 `HOOK_EVENTS`
里**没有**这个事件（“模型输出后”CC 用 `Stop` + `last_assistant_message`
字段表达）。因有下游消费方 （`ui_customizations.R`），暂保留不废弃，挂
TODO 待未来评估合并进 `Stop`。 - 新增/改名 hook 事件时，优先对齐 CC
公开事件名；若 CC 无对应而 SDK 有，注明来源与语义层级（事件 vs
消息类型）， 避免再次同名漂移。

**每次改完代码必须重装包并更新 codegraph：**

``` r

pak::local_install(".", ask = FALSE, upgrade = FALSE)
```

``` bash
codegraph sync   # 更新符号索引，让 kiro/AI 工具看到最新代码
```

这确保 `codeagent chat` /
[`codeagent_app()`](https://kaipingyang.github.io/codeagent/reference/codeagent_app.md)
等用安装版运行的入口点使用最新代码。[`devtools::load_all()`](https://devtools.r-lib.org/reference/load_all.html)
只在当前 R session 里生效，launcher（`--vanilla`）和 CLI
用的是已装的包。codegraph 不会自动同步，手动 sync 后 kiro 的 codegraph
审核才能看到新符号。

> **测试无误 = 要装到本地才算数。** 每次改完代码、跑完测试后，务必
> `pak::local_install(".", ask = FALSE, upgrade = FALSE)`
> 把**当前版本装到本地**——`load_all()` 只在当前 session
> 生效，真实验证/CLI/launcher 跑的是已安装的包。

**新增功能必须同步更新 README.md：** - 新导出函数/新 feature → 在 README
对应 section 补一行 - 重要行为变更 → 更新 README 相应描述 - README 79
commits 不更新已是教训：每次 commit 前检查 README 是否需要同步

**改代码必须同步更新测试和 example：** - 新增/修改函数 → 对应
`tests/testthat/test-*.R` 补测试 - 修改公开 API（签名/行为）→ 对应
`inst/examples/demo_*.R` 或 `test_databricks.R` 更新 - 新功能 → 加进
`inst/examples/test_databricks.R` 的 section -
**新增任何导出函数，必须同时：① 确认是否需接入
[`.register_all_tools()`](https://kaipingyang.github.io/codeagent/reference/dot-register_all_tools.md)/调用链；②
同步写 `test-*.R` 覆盖主路径和降级路径；③ 加进 `_pkgdown.yml` 的
reference 索引（对应 section 补一行）——否则 pkgdown CI 报
`topic missing from index` 挂掉（血泪：`data_shield_ocr_scanner` 漏加致
pkgdown build 失败）。改完跑
[`pkgdown::check_pkgdown()`](https://pkgdown.r-lib.org/reference/check_pkgdown.html)
应 `No problems found`。**

**工具函数用闭包工厂模式：**

``` r

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

------------------------------------------------------------------------

**依赖包版本（当前已装，2026-08-11 dev HEAD）：** - `ellmer`
0.4.2.9000（dev，需 `Remotes: tidyverse/ellmer`；含
`set_model()`/`chat_posit()`/`finish_reason`/`Chat$token_count()`；`Model`
类已从 `Provider` 拆出，`chat_github()` defunct） - `btw`
1.4.0.9000（dev，含 `btw_tool_files_patch` 原子多文件编辑、`agents/`
子目录发现、`btw pkg desc`/`pkg src` CLI） - `shinychat`
0.4.0.9000（dev，monorepo，安装路径：`pak::pak("posit-dev/shinychat/pkg-r")`，注意不是
`pak::pak("posit-dev/shinychat")`；含官方
`tool_result_display()`+`chat_ui(tool_grouping=)`+`<shiny-aside>`
citation） - `bslib` 0.12.0.9000（dev，含 `offcanvas()` 滑出面板 + 右侧
sidebar resize handle） - `shiny` 1.14.0.9000（dev，含 `startApp()`
非阻塞启动、`session$destroy()` 模块清理、`offcanvas()`） - `mcptools`
1.0.0（CRAN，含图片双向内容 + 认证远程 server + `_server.yml` Connect
部署） - `httr2` 1.3.0（CRAN，200x 流式加速 + `httr2_translate()` +
OTel）

``` r

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

**Non-ASCII in source:** R CMD check rejects non-ASCII characters in R
source files. Use `\uXXXX` escapes only inside string literals — **not**
in roxygen `#'` comments.

**`coro::for` inside
[`coro::async`](https://coro.r-lib.org/reference/async.html):** Write
plain `for (x in gen)` — do not qualify as `coro::for`. Do not wrap in
[`tryCatch()`](https://rdrr.io/r/base/conditions.html) inside the loop.

**No `x <- if (...)` inside a
[`coro::async`](https://coro.r-lib.org/reference/async.html) body:**
coro rewrites `if` as control flow and **cannot assign the result of an
`if` expression** (fails with coro `expr_info`: “Can’t assign the result
of a `if` expression”). Assign inside each branch instead
(`if (cond) { x <- a } else { x <- b }`), or compute the value *before*
the async body. Likewise avoid bare `!!!` splicing inside a coro body —
use [`do.call()`](https://rdrr.io/r/base/do.call.html). Also:
[`coro::async()`](https://coro.r-lib.org/reference/async.html) takes a
**literal** anonymous function (it
[`substitute()`](https://rdrr.io/r/base/substitute.html)s the arg), so
you cannot wrap a dynamically-built function with it — return a
[`promises::then()`](https://rstudio.github.io/promises/reference/then.html)
promise from a plain function instead (ellmer’s `invoke_tools_async()`
awaits any returned promise). See
`lessons/2026-07-03-shiny-async-interaction.md` and `R/tools_builtin.R`
`.asyncify_gated_tool()`.

**[`mirai::mirai_map()`](https://mirai.r-lib.org/reference/mirai_map.html)
常量必须走 `.args`，不能用 `...`：** mirai (\>= 2.x，验证于 2.7.1)
**不会**把 `...` 里的具名参数绑定到 worker 进程 —— worker 里那些参数是
missing，函数报 `argument "x" is missing, with no default`，mirai 返回
`miraiError` 对象而非你的返回值。
正确写法：`mirai_map(items, fn, .args = list(k1 = v1, k2 = v2))`（`.args`
绑定 + 保序）。 另注意
[`is.character()`](https://rdrr.io/r/base/character.html) 对
`miraiError` 返回 **TRUE**，判定 worker 是否失败要用
`inherits(x, "miraiError")` 而非字符串检查。参考 `R/team.R`
[`team_run()`](https://kaipingyang.github.io/codeagent/reference/team_run.md)
与 `R/team_board.R`
[`team_coordinate()`](https://kaipingyang.github.io/codeagent/reference/team_coordinate.md)
的 worker_loop（两处都用 `.args`）。worker 闭包若引用
包内部函数（非导出），把函数的
[`environment()`](https://rdrr.io/r/base/environment.html) 设成
`asNamespace("codeagent")` 即可解析。

**Env vars:** Use `CODEAGENT_BASE_URL`, `CODEAGENT_MODEL`,
`CODEAGENT_API_KEY` (not `OPENAI_*`).

**Shiny layout rule:** Before changing chat/sidebar layout, read
`~/.claude/docs/bslib-shinychat-layout.md`. In particular,
`shinychat::chat_ui(fill = TRUE)` must live inside a truly fillable
parent (for example `bslib::sidebar(fillable = TRUE, ...)`), and extra
wrappers often break sticky-bottom input behavior.

**Shiny component rule:** Prefer
[`bslib::toolbar()`](https://rstudio.github.io/bslib/reference/toolbar.html)
for compact action rows and prefer
[`bslib::show_toast()`](https://rstudio.github.io/bslib/reference/show_toast.html)
over
[`shiny::showNotification()`](https://rdrr.io/pkg/shiny/man/showNotification.html)
for user-facing status feedback. Read
`~/.claude/docs/bslib-toolbar-toast.md` and
`~/.claude/docs/bslib-toast-vs-notification.md` before introducing new
action bars or notifications.

**Shiny state rule:** Use a single
[`shiny::reactiveValues()`](https://rdrr.io/pkg/shiny/man/reactiveValues.html)
for shared session state (see `ui.R` `state <- reactiveValues(...)`). Do
NOT scatter individual `reactiveVal()` objects — consolidate related
reactive state into one `reactiveValues` container. When mutable
cross-module state is needed (e.g. the active client/chat for model
switching), add a slot to the shared `reactiveValues`, not a standalone
`reactiveVal`.

**Shiny promise-in-observer rule (CRITICAL):** Never let a
`promise(...)` call be the **last expression** in an `observeEvent` /
`observe` body. If it is, Shiny treats the observer as an *async
observer* and holds the reactive flush open until the promise settles —
so any UI invalidations triggered inside the observer (e.g. writing
`state$pending_approval`) are never flushed to the browser until the
promise resolves. For “pause and wait for user interaction” patterns:

``` r

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

The `resolve` function stored in `state$pending` is called later from an
Allow/Deny observer (which has the correct reactive domain). Never use
[`later::run_now()`](https://later.r-lib.org/reference/run_now.html) to
“pump” the event loop inside a Shiny observer — the reactive graph is
non-reentrant and will block. Never use
[`promises::then()`](https://rstudio.github.io/promises/reference/then.html)
for UI updates in Shiny — `then()` callbacks run in the `later` queue
with NULL reactive domain and cannot write to `reactiveValues`.

**Shiny async tool approval pattern:** For approval/question bars (tool
gate UI in Shiny), use
`chat_ui(footer = tagList(uiOutput("ca_approval_ui"), uiOutput("ca_question_ui")))`
— the `footer=` slot is rendered above the input box. Bars use
`border-top` only (no coloured backgrounds). Reference implementation:
`inst/examples/test_shiny_ask_fn.R`.

------------------------------------------------------------------------

## Architecture

### Entry point / data flow

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

> **Tool permissions = one central gate** (`R/tools_gate.R`,
> `.install_permission_gate`). All tools (native + btw + Format + MCP)
> are built ungated (`mode="bypass"`) and governed uniformly by ellmer’s
> rejectable `on_tool_request` (sync) / `maybe_on_tool_request_async`
> (Shiny). Fine-grained control via `settings$tools`
> (`sets`/`capabilities`/`overrides`); see README → Tool permission
> control.

### Client object model

``` r

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

**`query.R`** —
[`codeagent_client()`](https://kaipingyang.github.io/codeagent/reference/codeagent_client.md)
is the primary factory; builds `CodeagentClient` S3 object.
[`codeagent()`](https://kaipingyang.github.io/codeagent/reference/codeagent.md)
dispatches new/legacy style.
[`agent_loop()`](https://kaipingyang.github.io/codeagent/reference/agent_loop.md)
is called per-turn (was `query_loop`).
[`.register_all_tools()`](https://kaipingyang.github.io/codeagent/reference/dot-register_all_tools.md)
wires all tool groups. `.handle_agent_error()` classifies
PTL/rate-limit/network/auth errors with backoff.
[`verify_r_tests()`](https://kaipingyang.github.io/codeagent/reference/verify_r_tests.md)
is a built-in verify function.

**`permissions.R`** — **Seven-mode** gate:
`default / plan / accept_edits / bypass / dont_ask / auto / bubble`.
`bubble` returns `"ask"` to bubble permission up to parent agent
(sub-agent mode). `auto` uses haiku ML classifier. `DenialTracker` emits
warnings.

**`hooks.R`** — `HookRegistry` with **12 lifecycle events** via
`HookEvent$*`: tool events (`PreToolUse`, `PostToolUse`,
`PostToolUseFailure`), permission events (`PermissionDenied`,
`PermissionRequest`), message events (`UserMessage`,
`AssistantMessage`), and lifecycle events (`SessionStart`, `Stop`,
`PreCompact`, `SubagentStart`, `SubagentStop`). Mount points:
`agent_loop` fires SessionStart(iter 1)/Stop(all terminal
returns)/PreCompact(before maybe_compact); `agent_tool` fallback fires
SubagentStart/Stop. Legacy `register_pre()`/`register_post()` still
work.

**`tools_builtin.R`** — 8 core tools (Bash, Read, Write, Edit,
MultiEdit, Glob, Grep, LS). All return `ContentToolResult` with
`extra$display` (HTML title + markdown) for shinychat tool cards. All
have `_intent` parameter for card display.

**`tools_r.R`** — Wraps
[`btw::btw_tools()`](https://posit-dev.github.io/btw/reference/btw_tools.html).
`.BTW_GROUPS` covers all 10 btw 1.2.1 groups:
`agent, cran, docs, env, files, git, ide, pkg, sessioninfo, web`.
`btw_tool_skill` excluded (handled by skill system).

**`tool_run_r.R`** —
[`run_r_tool()`](https://kaipingyang.github.io/codeagent/reference/run_r_tool.md)
wraps
[`btw::btw_tool_run_r()`](https://posit-dev.github.io/btw/reference/btw_tool_run_r.html)
(arbitrary R execution, no sandbox) behind the **permission gate** under
tool name `"RunR"`. `destructive_hint=TRUE`, never read-only → `default`
mode resolves to `"ask"` (user confirms each call), `plan`/`dont_ask` →
`deny`, `bypass` → allow. btw excludes `btw_tool_run_r` from default
`btw_tools()`, so the gated wrapper is the only execution path.
`.runr_to_tool_result()` is a special case of the `tool_display.R`
adapter.

**`tool_display.R`** — **typed tool-artifact contract + render
dispatcher**. The typed artifact lives under
`extra$codeagent$artifact = {kind, status, icon, title, payload}` — a
**private key ellmer only transports** (never read), so shinychat never
warns “Unrecognized field” (plan 35 B1: previously
`extra$display$toolcard`/`right_output`, which shinychat’s
`as_tool_result_display()` warned on + dropped).
`kind ∈ {code, image, table, diff, text, error}`. `display` now carries
ONLY shinychat-official fields:
`title`/`icon`/`markdown`/`html`/`full_screen`/`open`.
[`.tool_result2()`](https://kaipingyang.github.io/codeagent/reference/dot-tool_result2.md)
builds the artifact on `extra$codeagent`, then renders the rich card
ONCE into `display$html` (in-chat bubble, rendered natively by shinychat
inside `<shiny-tool-result>`, `full_screen=TRUE` + `open=FALSE` =
collapsed/expandable). The right Output panel re-renders **on demand**
from the artifact (`server_chat.R` `.push_output` calls
`render_artifact(artifact, mode="panel")`) — no stored `right_output`
copy. `render_artifact(artifact, mode=c("panel","bubble"))` is the
dispatcher (code→Prism-highlighted+copy, image→zoomable img+toolbar,
table→reactable, diff→base-R-LCS colored, error→styled box); the `mode`
param is wired for future bubble/panel differentiation but currently
renders identically (step 2, separately scheduled — differentiated
views + A2UI). `.adapt_tool_result(result)` is the **universal adapter**
called at the `server_chat.R` `on_tool_result` boundary — normalizes ANY
native `ContentToolResult` (raw
[`btw::btw_tools()`](https://posit-dev.github.io/btw/reference/btw_tools.html),
web, skills) into the typed contract, idempotent (checks
`extra$codeagent$artifact` OR legacy `extra$display$toolcard` for old
sessions). The 8 builtins + RunR use
[`.tool_result2()`](https://kaipingyang.github.io/codeagent/reference/dot-tool_result2.md);
everything else gets typed by the adapter. Interactivity
(copy/zoom/fullscreen/download) is document-delegated JS in `agent.js`;
CSS classes `.toolcard-*` + `data-toolcard-*` attributes in `styles.css`
(unchanged across migration); Prism.js via CDN in `head_assets()`.

**`tools_agent.R`** —
[`agent_tool()`](https://kaipingyang.github.io/codeagent/reference/agent_tool.md)
uses `btw_tool_agent_subagent` when btw available; falls back to
codeagent’s own loop. Supports `worktree_isolation=TRUE` (git worktree
per sub-agent). Discovers custom agents from `.btw/agent-*.md`,
`.claude/agents/`.
[`codeagent_mcp_server()`](https://kaipingyang.github.io/codeagent/reference/codeagent_mcp_server.md)
wraps
[`btw::btw_mcp_server()`](https://posit-dev.github.io/btw/reference/mcp.html).
[`install_codeagent_cli()`](https://kaipingyang.github.io/codeagent/reference/install_codeagent_cli.md)
installs Rapp-based CLI.

**`mcp_client.R`** — **MCP client (M8)**.
`register_mcp_client(chat, config)` wraps
[`mcptools::mcp_tools()`](https://posit-dev.github.io/mcptools/reference/client.html)
to connect EXTERNAL MCP servers (stdio transport via processx child
process) and register their tools onto the Chat. Config = JSON path or
inline list (`mcpServers: {name: {command, args, env}}`).
`codeagent_client(mcp_config=)` opts in. Complements
[`codeagent_mcp_server()`](https://kaipingyang.github.io/codeagent/reference/codeagent_mcp_server.md)
(server side). Graceful: missing mcptools/bad config → 0 tools, no
crash. Sandbox (fs/network isolation) NOT implemented — see
`references/sandbox-limitations.md` (権限门控 + Hook 策略 is the
security model; OS/container sandbox is host-layer responsibility).

**`compaction.R`** — **Five-level** compaction: - L1 `snip_old_tools`:
replace large old tool results with placeholder - L2
`session_memory_compact`: summarise early turns via compact model - L3
`full_compact`: fork agent → 9-section `<summary>` - L4 `ptl_fallback`:
drop oldest turns on 413 errors - L5 `context_collapse`: read-time
projection (truncate all tool result values)

> **Current flow (task 01 alignment):** the live `maybe_compact()`
> trigger is now **two-level** — `snip_old_tools` pre-step →
> `session_memory_compact` → fall back to `full_compact` (verbatim
> 9-section prompt). `ptl_fallback`/`context_collapse` remain as
> reactive/utility paths. Dynamic per-model window lives in
> `R/context.R`. **Known gap (mostly closed):** turn-boundary compaction
> runs before each `chat$chat()`. Between tool rounds,
> [`register_midloop_compaction()`](https://kaipingyang.github.io/codeagent/reference/register_midloop_compaction.md)
> (ellmer’s released `on_tool_result`) compacts in two tiers mirroring
> CC `autoCompactIfNeeded`: a **budget-aware micro snip** ON by default
> (`settings$midloop_compact`) and an **opt-in full two-level compact**
> (`settings$midloop_full_compact`) via
> `CompactionController$compact_now()`. Remaining gap is *timing*:
> `on_tool_result` only fires between tool rounds, not before every
> request. `on_tool_request` cannot substitute (it fires after the
> request, inside `invoke_tools`, per tool). True parity needs upstream
> `on_turn_start` (PR tidyverse/ellmer#1052); see
> `references/plan/13-mid-loop-compaction.md`.

**`tools_web.R`** —
[`web_fetch_tool()`](https://kaipingyang.github.io/codeagent/reference/web_fetch_tool.md)
and
[`web_search_tool()`](https://kaipingyang.github.io/codeagent/reference/web_search_tool.md).
All tools return `ContentToolResult` with `extra$display` (HTML title +
markdown preview for humans). WebSearch backend: `BRAVE_API_KEY` → Brave
Search API (real results, 2000 free/month); fallback → DuckDuckGo
Instant Answer (entity queries only, no key needed). WebFetch uses httr2
directly (no Chrome dependency). btw `web_read_url` (needs Chrome) is
available as extra via `btw_groups = "web"`.

**`skills.R`** — **btw-compatible** skill system. Skill format:
`<name>/SKILL.md` directories (not flat `.md` files). Uses
`btw:::btw_skills_list()` as primary discovery backend. Discovery paths:
codeagent `inst/skills/` + btw paths + `.btw/skills/` +
`.agents/skills/` + `.claude/skills/` + `.codex/skills/`.
[`.make_skill_tool()`](https://kaipingyang.github.io/codeagent/reference/dot-make_skill_tool.md)
registers `use_skill` ellmer tool for LLM semantic auto-trigger; returns
`ContentToolResult` with HTML title card. **Metadata cache (2-tier):**
[`list_skills_meta()`](https://kaipingyang.github.io/codeagent/reference/list_skills_meta.md)
caches parsed metadata in-memory AND on disk (`.skill_cache_read/_write`
under `<config>/cache/skills/`, keyed by cwd + a `SKILL.md` mtime/count
signature `.skill_dirs_mtime_sig`). A disk hit returns *before*
`btw:::btw_skills_list()` runs, so a fresh process skips the slow scan;
atomic temp+rename writes, best-effort I/O (corrupt/missing cache → full
rescan). Two trigger paths: user `/name` →
[`load_skill_prompt()`](https://kaipingyang.github.io/codeagent/reference/load_skill_prompt.md)
inject; LLM semantic match → `use_skill` tool call. User custom skills:
use `~/.btw/skills/` (not `~/.codeagent/skills/`).

**`client_config.R`** — `codeagent_client_config(alias=)` reads
`codeagent.md` / `.codeagent/config.md`. Supports single client spec
(`"openai/model"`) or alias maps with interactive selection.
[`use_codeagent_md()`](https://kaipingyang.github.io/codeagent/reference/use_codeagent_md.md)
creates template.

**`memory.R`** — **auto-memory (M6)**. Persistent agent memory under
`~/.codeagent/memory/<slug>.md` (YAML front-matter
`name`/`description` + body) + `MEMORY.md` index.
`write_memory/list_memories/recall_memories/delete_memory`. The
`remember` tool (`register_memory_tool`) lets the LLM persist durable
facts;
[`recall_memories()`](https://kaipingyang.github.io/codeagent/reference/recall_memories.md)
is injected into `.build_system_reminder` on iteration 1 (not every turn
— model retains it after). Survives across sessions.

**`model_switch.R`** — **lossless model switch (M1)**.
`switch_model(client, model)`: Route A swaps ellmer R6
`private$provider` in place (same Chat object →
callbacks/stream_controller/closures untouched); Route B (tryCatch
fallback) rebuilds via public API. `.resolve_model_chat` reuses
`client_config` alias resolution. Shiny uses `.swap_provider` directly
(Route A only, to keep Chat identity); CLI uses full `switch_model`. See
`references/model-switch-alternatives.md`.

**`settings.R`** — Priority: env vars \> `~/.codeagent/settings.json` \>
`.codeagent/settings.json` \> defaults.
[`.build_system_reminder()`](https://kaipingyang.github.io/codeagent/reference/dot-build_system_reminder.md)
injects ephemeral per-turn context (date/iteration/cwd) into user
message (not system prompt) to preserve prompt cache.

**`compaction.R` `.make_compact_chat()`** — When `CODEAGENT_BASE_URL`
set, uses `chat_openai_compatible` with `databricks-claude-haiku-4-5`;
otherwise `chat_anthropic`.

**`ui.R`** —
`codeagent_app(client, pinned_skills, theme, port, launch.browser)`.
**Instant startup**: the UI shell renders first; tool + skill
registration is deferred into a `session$onFlushed()` step behind a
full-window “Initializing codeagent…” overlay
(`uiOutput("ca_init_overlay")` gated on `state$initializing`), with the
chat input disabled until it completes. Pass a bare ellmer `Chat` (not a
pre-built `CodeagentClient`) to get the lazy path — `codeagent_app` then
builds a cheap shell client (`register_tools=FALSE`) and registers tools
in-server. Sidebar accordions: Sessions (1st, open), Customizations,
Settings (permission mode + btw tool groups + theme toggle). Skills are
NOT a sidebar panel — they ride shinychat’s slash-command typeahead
(type `/`; see `server_slash.R`). Right output panel (`ui_panels.R`
`output_panel_ui`) has three **static** navset tabs: Output / Files
(jsTreeR tree) / File (single scrollable viewer driven by
`server_right.R`’s `ca_file_view` reactiveVal — clicking a file renders
its preview there; NB: do NOT reintroduce per-file `nav_insert()` tabs,
which mis-render outside the navset and cover the tab strip). Themes:
`"default"` (pure bslib), `"flatly"`, `"darkly"` (Bootswatch), `"glass"`
(custom). Tools stream via `stream="content"` → shinychat renders tool
cards automatically.

**`sessions.R / mutations.R`** — Sessions stored as JSONL under
`~/.codeagent/projects/<hash>/`. Session titles fall back to first user
message (not UUID).
[`fork_session()`](https://kaipingyang.github.io/codeagent/reference/fork_session.md)
implemented. **Lossless persistence (M7)**: `save_session` writes a
`chat-state` line (`contents_record` → gzip → base64, JSON-safe)
preserving tool requests/results; per-message text lines remain for UI
display + legacy fallback.
`restore_session_into_chat(chat, session_id, cwd)` prefers the lossless
state (tool calls intact), falls back to text turns for pre-M7 sessions.
`session_id = NULL` → continue most recent (CLI `--continue`). Shiny
session-load + CLI `--continue`/`--resume` both use it.

### Key design decisions

- **[`codeagent_client()`](https://kaipingyang.github.io/codeagent/reference/codeagent_client.md)
  is the central factory**: takes any ellmer Chat, injects tools +
  system prompt, returns `CodeagentClient`. Both
  [`codeagent()`](https://kaipingyang.github.io/codeagent/reference/codeagent.md)
  and
  [`codeagent_app()`](https://kaipingyang.github.io/codeagent/reference/codeagent_app.md)
  accept `CodeagentClient` as first arg; old flat params still work for
  backward compat.
- **All tools return `ContentToolResult` with `extra$display`**: `title`
  (HTML, use
  [`htmltools::HTML()`](https://rstudio.github.io/htmltools/reference/HTML.html)),
  `markdown` (human-readable preview), `value` (LLM-facing text). See
  `ellmer-tool-calling.md` for the full `extra$display` field spec.
- **WebSearch backends**: `BRAVE_API_KEY` env var enables Brave Search
  API; without it falls back to DuckDuckGo (entity queries only). Never
  rely on DDG for general questions.
- **btw as tool layer**: codeagent is the harness
  (loop/permissions/compaction/hooks/skills); btw provides the
  R-environment tool set (docs/git/pkg/env/etc). They compose, not
  compete.
- **Skill format is `name/SKILL.md`** (btw/Claude Code compatible).
  Never use flat `.md` files.
- **`ContentToolResult` with `extra$display`**: all tools return typed
  results with HTML title + markdown for shinychat cards.
- **S7 slot access is fragile**: wrap in `tryCatch`.
- **`%||%` null-coalescing**: defined in `utils.R`.
- **shinyAssistantUI canonical groups**: when mimicking the slash menu,
  use the 6 fixed sections from `shinyAssistantUI` examples/source —
  `Context`, `Model`, `Customize`, `Slash Commands`, `Settings`,
  `Support`. Do not invent ad-hoc group names for the UI prototype
  unless the user explicitly asks.

### Runtime directories

| Path | Purpose |
|----|----|
| `~/.codeagent/settings.json` | User-global settings |
| `~/.codeagent/projects/<hash>/` | Session JSONL files |
| `~/.codeagent/tool-results/` | L2 large-result disk cache |
| `~/.codeagent/skills/` | User-global custom skills |
| `.codeagent/skills/` | Project-local skill overrides |
| `.codeagent/config.md` | Project-local multi-client config |
| `codeagent.md` | Project-local multi-client config (alt location) |
| `exec/codeagent.R` | Rapp CLI entry point |

------------------------------------------------------------------------

## What is implemented

All core subsystems are complete. 281 tests pass.

- ✅ Agent loop
  ([`agent_loop()`](https://kaipingyang.github.io/codeagent/reference/agent_loop.md))
  with max_turns, budget, compaction, hooks
- ✅ 7-mode permission system (includes `bubble`)
- ✅ 12-event hook system (`HookEvent$*`) —
  tool/permission/message/lifecycle
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
- ✅ Rapp CLI (`exec/codeagent.R`) —
  `run`(–model/–continue/–resume/–stream) + `chat`/`repl`(交互式
  REPL：readline loop + /model//compact//clear//help 斜杠命令 + 流式) +
  app/skills/mcp/info
- ✅ MCP server
  ([`codeagent_mcp_server()`](https://kaipingyang.github.io/codeagent/reference/codeagent_mcp_server.md)) +
  MCP client
  ([`register_mcp_client()`](https://kaipingyang.github.io/codeagent/reference/register_mcp_client.md),
  stdio)

------------------------------------------------------------------------

## Backlog（后续计划）

对标 Claude Code
的已知缺口，按价值排序。实现前先确认上游（ellmer/btw/shinychat）是否已有原生支持。

> **状态核对（2026-08-13）**：原 backlog 的 P1/P2/P3
> 均已实现，下移到”已完成”。仅 P4/P5/语音仍待办。 更新前 P1/P2
> 标”待做”但实际早已接线，误导过判断——核对后修正，避免再次误判。

### 已完成（曾在 backlog，现已实现）

- ✅ **Shiny ask_fn 工具审批 UI**（原 P1）—
  `R/server_interaction.R`：`.shiny_ask_fn`（promise-returning， :26）+
  `ask_fn` 接线（:244）+ `ca_tool_allow`/`ca_tool_deny` 按钮 +
  observeEvent。`ui.R:385-388` 把
  `shiny_ask_fn`/`shiny_ask_question_fn`/`egress_ask` 三条审批线全注入
  session。footer inline bar 版 （`chat_ui(footer=)`），promise +
  `.resolve_pending` 桥接。**三条审批线**：权限
  Allow/Deny、AskUserQuestion 问答、数据盾
  egress（redact/block/raw-once）。
- ✅ **AskUserQuestion 工具**（原 P2）—
  `R/tools_ask_user.R`：[`ask_user_tool()`](https://kaipingyang.github.io/codeagent/reference/ask_user_tool.md) +
  [`register_ask_user_tool()`](https://kaipingyang.github.io/codeagent/reference/register_ask_user_tool.md)
  （query.R:705 注册）。CLI 走 `readline`/test 覆盖，Shiny 走
  `.shiny_ask_question_fn` 异步 promise。
- ✅ **工具并发执行**（原 P3）— ellmer 已原生支持，codeagent
  `tool_mode="concurrent"` 默认透传
  `chat$stream_async(tool_mode=)`（stream.R:74/133）。并发只加速 async
  工具（如子agent），同步 CLI 工具仍串行 （ellmer
  语义）。不自实现调度，直接受益上游。

### P4 — `@path` import in CLAUDE.md（真未实现）

Claude Code 支持 CLAUDE.md 中用 `@/path/to/file.md`
内联引用外部文件。当前
[`.load_claude_md()`](https://kaipingyang.github.io/codeagent/reference/dot-load_claude_md.md)
（settings.R）只加载 CLAUDE.md 本体，**不解析 `@` 引用**（已核实）。

**实现**：[`.load_claude_md()`](https://kaipingyang.github.io/codeagent/reference/dot-load_claude_md.md)
读取每个文件后，正则扫描 `^@(.+)` 行，递归读取引用文件并替换。
注意循环引用保护（`seen` set 已有，复用即可）。**小功能，价值中低**。

### P5 — Dollar budget（成本控制，真未实现）

Claude Code 有 `maxBudgetUsd`，按 API 成本限制。当前只有 token
budget（`chat$get_cost()` 已能读成本， 但无 USD 上限熔断）。

**低优先级**：需维护各 provider token 价格表（ellmer
`models_update_prices()` 可拉，但仍需接线）。 等有明确需求再做。

### 语音输入

**等上游**：JamesHWade 的 shinychat `feature/audio-input`
分支（`audio_input="transcribe"` 参数）完成后，codeagent 只需在
`ui_panels.R`
加一个参数。不自己实现。进展跟踪：<https://github.com/posit-dev/shinychat/issues/146>
