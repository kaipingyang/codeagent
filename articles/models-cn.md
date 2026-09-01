# 模型和供应商（简体中文）

**语言：**
[English](https://kaipingyang.github.io/codeagent/articles/models.md) \|
简体中文

`codeagent` 可以包装任意已配置的
[`ellmer::Chat`](https://ellmer.tidyverse.org/reference/Chat.html)。直接传入
Chat 是最通用、
歧义最少的供应商接口；基于设置的工厂则为常见后端提供便利。

## 传入任意 ellmer Chat

``` r

chat <- ellmer::chat_openai_compatible(
  base_url = Sys.getenv("CODEAGENT_BASE_URL"),
  model = Sys.getenv("CODEAGENT_MODEL"),
  credentials = function() Sys.getenv("CODEAGENT_API_KEY"),
  preserve_thinking = TRUE
)

client <- codeagent_client(chat, permission_mode = "default")
```

其他示例使用供应商原生的 ellmer 认证：

``` r

anthropic_client <- codeagent_client(
  ellmer::chat_anthropic(model = "claude-sonnet-4-6")
)

ollama_client <- codeagent_client(
  ellmer::chat_ollama(model = "llama3.2")
)
```

提供 Chat 后，codeagent 会用 harness 提示替换其系统提示，并记录当前模型
名称。除此之外，它会保留 Chat 的供应商配置和模型参数。

## 自动选择供应商

当 `chat = NULL`
时，[`codeagent_client()`](https://kaipingyang.github.io/codeagent/reference/codeagent_client.md)
会调用内部设置工厂。选择顺序为：

1.  显式的 `provider` 设置；会先移除可选的 `chat_` 前缀；
2.  存在 `base_url`/`CODEAGENT_BASE_URL` 时使用 `openai_compatible`；
3.  否则使用 `anthropic`。

当前工厂为以下值提供分支：

- `openai_compatible`、`openai`、`vllm` 和 `lmstudio`；
- `anthropic` 及其 `claude` 别名；
- `ollama`；
- `databricks`、`deepseek`、`google_gemini`、`google_vertex`、`groq` 和
  `github`；
- `aws_bedrock`、`azure_openai`、`mistral`、`perplexity`、`portkey`、
  `posit`、`huggingface`、`cloudflare`、`snowflake` 和 `openrouter`。

每个值都会解析为对应的 `ellmer::chat_<provider>()` 函数，该函数必须存在
于已安装的 ellmer 版本中。认证要求取决于供应商。接收显式凭据闭包的工厂
会使用 `api_key_env` 指定的环境变量，默认是 `CODEAGENT_API_KEY`；
Anthropic、Bedrock、Vertex、Posit 和其他原生流程可以依赖 ellmer 自身的
环境变量、IAM 或 OAuth 行为。

对于 OpenAI 兼容网关：

``` json
{
  "provider": "openai_compatible",
  "model": "main",
  "env": {
    "CODEAGENT_BASE_URL": "https://YOUR-WORKSPACE/serving-endpoints",
    "CODEAGENT_MODEL": "your-main-endpoint"
  }
}
```

把相应密钥保留在 JSON 之外。

## 模型规格和别名

[`codeagent_client_config()`](https://kaipingyang.github.io/codeagent/reference/codeagent_client_config.md)
和
[`switch_model()`](https://kaipingyang.github.io/codeagent/reference/switch_model.md)
都以同一个较小的模型规格 解析器为基础。它可识别的前缀为：

| 规格 | 构造函数 |
|----|----|
| `openai/<model>` | 设置了 `CODEAGENT_BASE_URL` 时使用 `chat_openai_compatible()` |
| `anthropic/<model>` | `chat_anthropic()` |
| `ollama/<model>` | `chat_ollama()` |
| 纯模型名称 | 使用该模型的自动设置工厂 |

别名在 `codeagent.md` 中定义：

``` yaml
---
client:
  main-gateway: openai/gpt-4.1
  direct-claude: anthropic/claude-sonnet-4-6
  local: ollama/llama3.2
---
Project instructions follow here.
```

``` r

client <- codeagent_client_config(alias = "main-gateway")
```

## 在不丢失历史的情况下切换模型

始终为结果赋值，因为切换可能返回同一个客户端，也可能返回重建后的客户端：

``` r

client <- switch_model(client, "anthropic/claude-haiku-4-5")
```

[`switch_model()`](https://kaipingyang.github.io/codeagent/reference/switch_model.md)
会先把目标解析为一个新的 Chat，然后选择两条经过验证的 路径之一：

- **Route A，仅名称：** 如果供应商配置、凭据、模型参数和 API 参数均未
  改变，`set_model()` 只更改名称。Chat/客户端身份、工具、回调和历史记录
  都保持不变。
- **Route B，重建：** 供应商、端点、凭据、参数或 API 参数发生变化时，
  构建新的 Chat/客户端。轮次、系统提示、工具、实时设置、hooks、MCP
  配置、 预算和实时 Data Shield
  都会迁移。如果重建失败，原客户端保持不变。

CLI 和直接 R API 接受两条路径。Shiny 模块会捕获 Chat 身份，因此 Settings
中的模型控件和 `/model` 只允许经过验证的 Route A 切换，并会在响应正在
流式传输时拒绝切换。需要 Route B 的目标必须用所需配置启动新的 Shiny
会话/应用。

## 推理和 thinking 内容

对于自动构建的 Chat，请设置 snake_case 的 `effort_level` 字段：

``` json
{
  "effort_level": "high"
}
```

非空时，它会按以下形式传递：

``` r

ellmer::params(reasoning_effort = "high")
```

请使用所选模型/供应商支持的值，常见值包括 `low`、`medium`、`high` 或
`xhigh`。codeagent 在原样传递之前不会验证该值。camelCase 字段
`effortLevel` 不会被自动 Chat 工厂使用。传入显式 Chat 时，请自行配置其
`params`：

``` r

chat <- ellmer::chat_openai_compatible(
  base_url = Sys.getenv("CODEAGENT_BASE_URL"),
  model = Sys.getenv("CODEAGENT_MODEL"),
  credentials = function() Sys.getenv("CODEAGENT_API_KEY"),
  params = ellmer::params(reasoning_effort = "high"),
  preserve_thinking = TRUE
)
```

自动 `openai_compatible` 分支设置
`preserve_thinking = TRUE`。把推理暴露为
[`ellmer::ContentThinking`](https://ellmer.tidyverse.org/reference/Content.html)
的供应商可以把它流式传到 REPL 的暗色 thinking 显示中，并为
Shiny/会话重放保留它。这不会为本身不支持推理的模型启用 推理能力。

## Main、heavy 和 fast 层级

层级映射由以下变量构建：

| 层级 | 变量 | 自动角色 |
|----|----|----|
| `main` | `CODEAGENT_MODEL` | 默认当前模型和 `main` 别名。 |
| `heavy` | `CODEAGENT_HEAVY_MODEL` | 仅作为别名；codeagent 不会自动把困难任务升级到该模型。 |
| `fast` | `CODEAGENT_FAST_MODEL` | 压缩、自动权限分类、记忆相关性和可选 Data Shield review 的首选模型。 |

``` ini
CODEAGENT_MODEL=your-main-endpoint
CODEAGENT_HEAVY_MODEL=your-heavy-endpoint
CODEAGENT_FAST_MODEL=your-fast-endpoint
```

压缩依次优先使用 `CODEAGENT_FAST_MODEL`、option 覆盖、当前 Chat 的模型，
最后才使用内部 Haiku 后备。`auto` 权限模式同样优先使用 fast 模型，然后
在使用内部默认值之前回退到 main 模型。在私有 OpenAI 兼容网关中使用时，
请配置有效的 fast 端点。

## 上下文窗口

原始上下文窗口按以下顺序解析：

1.  正数 `CODEAGENT_MAX_CONTEXT_TOKENS`；
2.  模型名称中的 `[1m]` 后缀；
3.  可信的供应商报告值或内置已知模型表；
4.  200,000 tokens。

有效自动压缩窗口会预留输出空间。正数 `CODEAGENT_AUTO_COMPACT_WINDOW`
可以 降低该窗口，任意非空 `CODEAGENT_DISABLE_COMPACT`
都会禁用自动阈值压缩。 Token 计数会尽可能使用缓存的
usage，否则在本地估算；正常压缩/状态路径 不会隐式发起 token
计数网络请求。

## 成本数据和美元预算

客户端可以执行正数的美元上限：

``` r

client <- codeagent_client(max_budget_usd = 2.50)
```

同一设置也可通过 JSON 中的 `max_budget_usd` 或
`CODEAGENT_MAX_BUDGET_USD` 提供。它依赖 `chat$get_cost()`。如果 ellmer
没有自定义/私有模型的价格，成本可能一直为零，此时上限无法触发。

价格数据绝不会在启动或模型请求期间自动刷新。需要时请显式刷新 ellmer 的
公开价格快照：

``` r

price_update <- update_model_prices()
price_update$message
```

刷新失败时会保留现有缓存。即使刷新公开价格，私有端点仍可能没有匹配项。
