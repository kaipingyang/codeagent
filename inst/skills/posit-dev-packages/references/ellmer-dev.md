# ellmer 开发版新功能（vs CRAN 0.4.1）

当前安装：0.4.1.9000（GitHub: tidyverse/ellmer）

## 新 API

### `chat_posit()` + `models_posit()`
Posit AI 托管模型，通过 OAuth device flow 认证。无需 API key。
```r
chat <- ellmer::chat_posit(model = "claude-sonnet-4-6")
```
codeagent 已加入 `.PROVIDER_CATALOGUE`（`R/setup.R`）和 `.make_chat()`（`R/query.R`）。

### `Chat$set_model(model)`
运行时切换模型，不重建 Chat 对象。codeagent 已用于 `R/model_switch.R`。

### `type_ignore()`
标记工具参数"不让 LLM 填写"（有默认值的内部参数）。
```r
ellmer::tool(
  fun = function(x, _intent = NULL) ...,
  arguments = list(
    x = ellmer::type_string("the thing"),
    `_intent` = ellmer::type_ignore()  # LLM 不会看到这个参数
  )
)
```

### `tool(name = ...)` 参数
给工具指定稳定名称，LLM 按名称调用。
```r
ellmer::tool(name = "Read", fun = function(file_path) ...)
```
codeagent 已在所有 8 个内置工具上使用（`R/tools_bash.R`、`R/tools_fs.R`、`R/tools_search.R`）。

### `params(reasoning_effort = ...)` 多 provider 支持
Claude（anthropic）、Gemini、Ollama 现在都支持 `reasoning_effort` 参数。
```r
chat_anthropic(params = ellmer::params(reasoning_effort = "high"))
```

### `chat_openai_compatible()` reasoning_content
DeepSeek、Databricks 等 OpenAI 兼容 endpoint 的 thinking 内容自动映射为 `ContentThinking`，不再需要手动 patch。

## 其他改动

- `chat()` 响应被截断/过滤时抛出警告（非静默失败）
- `chat_structured()` 响应不完整时报信息性错误
- `batch_chat()` 支持 Groq batch API 和 Gemini batch API
- `chat_google_gemini()` 默认模型改为 `gemini-3.5-flash`
- `AssistantTurn` 新增 `finish_reason` 属性（停止原因：stop/length/filter）
  - 注：当前 0.4.1.9000 尚未包含此功能，在更新的 dev 版本中

## 已经在 0.4.0/0.4.1 里、不是"新"的

- OpenTelemetry instrumentation（0.4.1）
- `stream_controller()`（0.4.1）
- `ContentThinking` 区分（0.4.1）
- `df_schema(df)`：描述 data.frame 结构，含数值范围和枚举值（0.4.0）
  - codeagent 已在 `R/tools_data.R` 用于 ExploreData schema 路径
