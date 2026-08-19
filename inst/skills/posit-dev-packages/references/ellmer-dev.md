# ellmer 开发版新功能（vs CRAN 0.4.2）

当前安装：`0.4.2.9000`（GitHub: `tidyverse/ellmer`）
当前 SHA：`19be478ebf1a2e5d2db96a8aeaca71592c8d3f26`
最后验证：2026-08-18

## 当前开发版新增功能

### 跨 provider 的 citation content（#1068）

ellmer 现在统一保留 OpenAI、Anthropic 和 Google 的 web search/fetch 引用信息，并在 chat history、最终 turn 及 `stream = "content"` 的渐进流中传递。

新增的一等内容模型包括：

- `ContentCitation`：引用及其所支持的回答文本；
- `Source` / `WebSource`：来源类型、URL 和可选标题；
- `grounded_span`：该来源支持的回答片段；
- `cited_quote`：provider 返回的来源证据；
- web search/fetch activity content。

对于能使用 provider 内置 web 工具的环境，ellmer 会自动把 provider 返回的 citation payload 规范化。例如 OpenAI/Claude 的内置 web search/fetch 可以产生上述 Content。

**codeagent 例外：**当前 endpoint 不能使用这些 provider 默认 web 工具，因此 codeagent 在 `R/tools_web.R` 自己实现并默认注册：

- `WebSearch`：Brave（配置 key 时）或 DuckDuckGo fallback；
- `WebFetch`：逐跳授权、pin 已验证地址的直接 fetch（Jina 转发已删除）。

这两个工具返回合法 `ContentToolResult`，并在 `extra$codeagent$sources` 保留结构化来源。它们不会自动在
assistant turn 中生成 ellmer `ContentCitation`；codeagent 使用下述 current-turn marker bridge 确定性生成 citation UI。

### 工具返回值在调用后立即规范化（#1077）

工具函数现在应返回以下类型之一：

- character string/vector；
- atomic vector；
- JSON 字符串（复杂结果建议使用 `jsonlite::toJSON()`）；
- 一个 `Content` 对象或 `Content` 对象列表；
- `NULL`。

直接返回普通复杂 `list` 或 `data.frame` 已弃用并会警告。规范化改在工具调用后立即发生，可更早暴露无效返回值。

**codeagent 兼容性：**自定义 WebSearch/WebFetch 已返回 `ContentToolResult`；核心 executor 契约和已抽查的其他内置工具返回 character/Content，未发现明确阻断。新增或第三方工具仍应避免直接返回 `data.frame`/复杂 `list`。

### Provider 修复

- `chat_databricks()` 现在始终在工具定义中发送 `parameters`，注册无参数工具不再报错（#1086）。
- Claude 5 及以上模型现在会被正确识别为支持原生 structured output，不再错误回退到工具模拟方案（#1087）。
- 同期还有模型定价数据维护和 reverse-dependency 检查。

## codeagent 已落地的 Plan 37 集成

### Model / Provider 切换

ellmer 拆出独立 `Model` 后，替换 private Provider 不会同步 Model。codeagent 已在运行时复现旧实现会形成
provider/model split-brain，因此现在只允许公开 `set_model()` 的严格 name-only 原地切换；provider 配置或
Model params/extra_args 有任何变化都重建 client。Shiny 为保持捕获的 Chat identity 会明确拒绝重建型切换。

### token、finish reason 与价格

- token 统计包含 `cached_input`，默认 `allow_network=FALSE`；compaction/context UI/teardown 不隐式调用远端
  `Chat$token_count()`；
- 同步、stream 和 Shiny 共用 finish-reason mapper，并在 output gate 前加入静态提示；
- `update_model_prices()` 是显式 opt-in 包装：只在用户调用时执行 `ellmer::models_update_prices()`，网络失败
  保留已有 cache；启动和模型请求绝不自动刷新，custom/private endpoint 仍可能没有价格。

### 自定义 web citation 与工具结果

codeagent 自定义 WebSearch/WebFetch 不会自动变成 ellmer `ContentCitation`。已落地的 bridge 让工具保存
`extra$codeagent$sources`，模型只输出 `[[cite:SOURCE_ID|visible claim]]`；服务器只接受当前-turn source，扫描、
escape 后确定性重建 shinychat aside。citation 模式 buffer-then-show，raw model custom element 不进入浏览器。

复杂 `list`/`data.frame` 工具结果也已在 host/btw/MCP/Data Shield 边界规范化为合法 `ContentToolResult`
或安全文本降级，不依赖弃用的隐式复杂返回值转换。

## CRAN 0.4.2 已包含的基线能力

以下能力已进入 CRAN 0.4.2，不再属于当前开发版相对 CRAN 的差异，但 codeagent 仍在使用：

- `Chat$set_model()`：`R/model_switch.R`；
- `chat_posit()` / `models_posit()`：`R/setup.R`、`R/query.R`；
- `tool(name = ...)`：稳定工具名称；
- `type_ignore()`：隐藏不应由 LLM 提供的工具参数；
- `ContentThinking` 和 OpenAI-compatible `reasoning_content`；
- `AssistantTurn@finish_reason`；
- `stream_controller()`；
- 截断/过滤响应的警告与 structured-output 错误处理。

上游比较：<https://github.com/tidyverse/ellmer/compare/dd1c8965c8e35d94a0fcaa6b452234e7e95e432d...19be478ebf1a2e5d2db96a8aeaca71592c8d3f26>
