# 上下文管理与压缩

**语言：**
[English](https://kaipingyang.github.io/codeagent/articles/compaction.md)
\| 简体中文

codeagent 通过轮次边界压缩、默认启用的工具轮次间结果裁剪，以及响应式的
prompt-too-long
恢复，把长对话保持在模型上下文窗口内。这些计数路径都不会隐式 发起远程
token 计数请求。

## 动态上下文窗口

原始上下文窗口按以下顺序解析：

1.  有效的正数 `CODEAGENT_MAX_CONTEXT_TOKENS`。
2.  模型名中的 `[1m]` 后缀，选择 1,000,000 token。
3.  若存在，则使用尽力读取的提供商报告能力；否则使用针对
    Claude、GPT、Gemini、 DeepSeek、Llama、Qwen 和 Mistral
    的最长子字符串内置表。所得能力只有在至少为 100,000 token
    时才会被接受，否则使用默认值。
4.  默认 200,000 token。

设置 `CODEAGENT_MODEL_LIMIT` 后，它会在加载设置后直接替换
`settings$model_limit`。轮次边界和通常的中途触发计算使用该值。

对于“剩余上下文”状态和动态自动压缩阈值，有效窗口为
`原始窗口 - 输出预留`；输出预留随模型而异，并以 20,000 token 为上限。
`CODEAGENT_AUTO_COMPACT_WINDOW`
可以限制此有效窗口计算所用的原始窗口。动态 阈值还会再减去 13,000 token
缓冲。

``` r

# 轮次边界压缩直接使用 settings$model_limit - 33,000。
# 默认 model_limit 为 200,000 时，约在 167,000 触发。
```

## Token 计数

`token_count_with_estimation(chat, allow_network = FALSE)`
首先使用最近一次记录的 API
用量，包括提供商报告的缓存输入。如果没有正数用量，则按本地对话文本约每
3.5 个字符一个 token 估算。只有显式使用 `allow_network = TRUE`
时，才可能调用 `chat$token_count(include = "complete")`。

## 五种机制与自动摘要流程

实现包含五种机制：

1.  **L1
    [`snip_old_tools()`](https://kaipingyang.github.io/codeagent/reference/snip_old_tools.md)**
    用小占位符替换符合条件的旧工具结果，不调用 LLM。
2.  **L2
    [`session_memory_compact()`](https://kaipingyang.github.io/codeagent/reference/session_memory_compact.md)**
    增量摘要早期轮次。
3.  **L3
    [`full_compact()`](https://kaipingyang.github.io/codeagent/reference/full_compact.md)**
    创建一个结构化的九节摘要，用它替换历史，并在安全时
    保留最新的纯用户轮次。
4.  **L4
    [`ptl_fallback()`](https://kaipingyang.github.io/codeagent/reference/ptl_fallback.md)**
    在 413/prompt-too-long 错误后丢弃最早轮次。
5.  **L5
    [`context_collapse()`](https://kaipingyang.github.io/codeagent/reference/context_collapse.md)**
    原地截断大型工具结果值；它不是常规自动摘要链的一部分。

`CompactionController$compact_now()` 先运行 L1，再尝试 L2。只有 L2
无法运行（例如 缺少足够的适合轮次）时才运行
L3。连续三次压缩失败会打开熔断器；压缩成功会重置 失败计数。

## 精确时机与默认值

    token 计数 = 最近记录的 API 用量（包括缓存输入）
                 否则按本地字符数/3.5 估算

    轮次边界 -- .turn_setup()，每次 chat$chat() 之前
      CompactionController$maybe_compact(
        model_limit = settings$model_limit, compact_model = 已解析的快速模型)

      已启用、失败次数 < 3、且 tokens >= model_limit - 33,000？
        是 -> compact_now()
                L1 snip_old_tools()
                L2 session_memory_compact()
                   或仅在 L2 未运行时执行 L3 full_compact()

    工具轮次之间 -- ellmer on_tool_result 回调
      settings$midloop_compact = TRUE（默认）
      且 tokens >= 中途触发阈值？

        默认路径：
          snip_old_tools(keep_recent_turns = 10,
                         target_tokens = 动态自动阈值 / 2)
          # 预算感知的微型裁剪；不调用 LLM

        settings$midloop_full_compact = TRUE（选择启用）路径：
          compact_now()
          # 阻塞式 L1 -> L2 或 L3；替代微型裁剪路径

    响应式 -- 提供商报告 413 / prompt too long
      ptl_fallback(chat, drop_turns = 3L, error_msg = message)
        能解析真实限制 -> 丢弃最早轮次，直到本地估算不超过该限制的 90%
        无法解析限制   -> 丢弃最早 3 个轮次
      随后错误恢复会重试请求

默认中途触发阈值为 `settings$model_limit - 33,000`。可以用正数
`settings$midloop_threshold` 或 `options(codeagent.midloop_threshold=)`
替换。 微型裁剪目标和保留的最近轮次数也可分别通过
`settings$midloop_snip_target` /
`options(codeagent.midloop_snip_target=)` 与
`settings$midloop_keep_recent` /
`options(codeagent.midloop_keep_recent=)` 替换。 当相应设置为 false
时，选项 `codeagent.midloop_compact` 和 `codeagent.midloop_full_compact`
也可以选择启用相应功能。

中途处理目前依附于
`on_tool_result`，因此在工具结果之后、后续模型轮次之前运行。
它不会在每个提供商请求之前运行。`on_tool_request`
无法弥补此时机差距，因为它在 模型请求之后、工具调用内部触发；上游
`on_turn_start` hook 才能提供更合适的时机。

## 剩余上下文指示器

REPL 与 Shiny 使用
[`calculate_token_warning_state()`](https://kaipingyang.github.io/codeagent/reference/calculate_token_warning_state.md)
显示“剩余 N% 上下文”。启用
自动压缩时，百分比相对于动态自动阈值，而不是完整原始窗口。警告、错误、压缩和
阻止状态使用不同缓冲，UI 会在跨过这些边界时改变级别。

## 相关签名与默认值

``` r

# 导出的 R6 控制器
ctrl <- CompactionController$new()
ctrl$maybe_compact(
  chat,
  model_limit = 200000L,
  compact_model = codeagent:::.HAIKU_MODEL
)
ctrl$compact_now(
  chat,
  compact_model = codeagent:::.HAIKU_MODEL
)
ctrl$handle_ptl_error(chat, error = NULL)
ctrl$reset_failures()
ctrl$failure_count()

# 这里列出内部辅助函数，以明确其运行默认值
codeagent:::token_count_with_estimation(chat, allow_network = FALSE)
codeagent:::ptl_fallback(chat, drop_turns = 3L, error_msg = NULL)
codeagent:::context_collapse(chat, max_chars = 200L)
```

实际压缩模型通常由客户端依次从 `settings$compact_model`、
`settings$small_fast_model`
和包内回退值中选择；调用方无需引用内部回退常量。

## 控制项

``` r

Sys.setenv(CODEAGENT_DISABLE_COMPACT = "1")     # 禁用自动压缩
Sys.setenv(CODEAGENT_MAX_CONTEXT_TOKENS = "500000")  # 覆盖原始窗口
# 从 REPL / Shiny 手动压缩，可附带聚焦说明：
# /compact
# /compact preserve debugging details and exact file paths
```

仅当 `CODEAGENT_DISABLE_COMPACT`
未设置或为空时，自动压缩才启用；任何非空值都会 禁用它。`/compact`
是本地斜杠命令，不是模型请求，并可携带可选的聚焦说明。
