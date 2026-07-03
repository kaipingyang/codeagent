# shinychat 开发版新功能（vs CRAN 0.4.0）

当前安装：0.4.0.9000（GitHub: posit-dev/shinychat/pkg-r）

**注意安装路径**：shinychat 是 monorepo，必须用：
```r
pak::pak("posit-dev/shinychat/pkg-r")
# 不能用 pak::pak("posit-dev/shinychat")，会报错找不到 R 包
```

**JS 层说明**：0.4.0.9000 使用 `lib/shiny/shinychat.js`（与 CRAN 0.4.0 相同的旧版 Web Component），
`lib/shiny/chat/chat.js` 是新版 Web Component（未启用）。slash palette UI 在 `shinychat.js` 里
已实现（`shiny-chat-slash-palette`、`update_slash_commands`），R 层 `chat_server()$slash_command()`
可正常使用。

---

## `chat_server()` — 核心新 API

`chat_server()` 是 `chat_mod_server()` 的替代（soft-deprecated at 0.5.0）。
**关键差异**：返回一个控制器对象，暴露一整套方法。

```r
server <- function(input, output, session) {
  mod <- shinychat::chat_server("chat", client, session = session)
  # mod 是一个环境对象，包含以下方法
}
```

### 返回值方法

| 方法 | 类型 | 说明 |
|------|------|------|
| `mod$last_turn` | reactive | 最新一轮 AssistantTurn |
| `mod$last_input` | reactive | 最新用户输入 |
| `mod$status` | reactive | `"streaming"` / `"idle"` |
| `mod$client` | active binding | 当前 Chat 对象（只读） |
| `mod$append(response, role)` | function | 追加消息到 UI |
| `mod$update_user_input(value, ...)` | function | 程序化填写输入框 |
| `mod$clear(messages, greeting, client_history)` | function | 清空对话 |
| `mod$set_greeting(greeting)` | function | 设置欢迎语 |
| `mod$set_client(new_client, sync)` | function | 运行时切换 client |
| `mod$slash_command(name, desc, handler)` | function | 注册 slash 命令 ⭐ |
| `mod$history$on_save(fn)` | function | 历史保存钩子 |
| `mod$history$on_restore(fn)` | function | 历史恢复钩子 |

---

### `mod$slash_command(name, description, handler)` ⭐ 最重要

注册原生 slash 命令。JS 层 `shinychat.js` 已内置 `shiny-chat-slash-palette` UI——
用户在输入框输入 `/` 自动弹出命令列表，选中后触发 handler。

**无参数命令（handler 无参数）：**
```r
mod$slash_command("compact", "Compact the context", function() {
  mod$append("Context compacted.", role = "assistant")
})
```

**带参数命令（handler 接受 `ContentSlashCommand`）：**
```r
mod$slash_command("rewind", "Rewind N exchanges", function(content) {
  # content@user_text 是用户在 / 命令后输入的文本
  n <- as.integer(content@user_text)
  mod$append(paste0("Rewound ", n, " turns."), role = "assistant")
})
```

**返回注销函数：**
```r
cancel_plan <- mod$slash_command("plan", "Enter plan mode", function() { ... })
# 动态移除命令
cancel_plan()
```

**`chat_server()` vs 我们现有的 slash 系统对比：**

| 维度 | codeagent 现有（`agent.js`） | shinychat 原生 |
|------|---------------------------|---------------|
| JS 层 | 自写 dropdown（`ca_slash_commands`） | shinychat 内置 `shiny-chat-slash-palette` |
| R 注册 | `session$sendCustomMessage("ca_slash_commands", ...)` | `mod$slash_command(name, desc, fn)` |
| 动态 add/remove | 不支持 | 支持（返回注销函数） |
| 参数传递 | 正则截取 string | `ContentSlashCommand@user_text` |
| 维护负担 | 我们自己维护 JS | shinychat 随版本维护 |

**未来迁移方向**：用 `chat_server()$slash_command()` 替代 `agent.js` 里的自定义
slash dropdown，以及 `R/server_chat.R` 里的 `ca_slash_commands` sendCustomMessage 逻辑。
迁移的前置条件是把 `server_chat.R` 的 streaming/tools 逻辑移到 `chat_server()` 之上。

**测试 app**：`/tmp/test_slash_app.R`（验证了 `chat_server()$slash_command()` 的 R 层 API）。

---

### `mod$set_client(new_client, sync = TRUE)` ⭐ 模型切换

```r
# sync=TRUE 把旧 client 的 turns/system_prompt/tools 复制到新 client
mod$set_client(new_client, sync = TRUE)
```

内部处理并发安全：如果当前正在 streaming，放入 `pending_swap` 队列，
等 streaming 完成后自动切换。**比我们手写的 model switch 逻辑更安全。**

---

### `mod$clear(messages, greeting, client_history)`

```r
mod$clear(
  messages      = list(list(role="assistant", content="已清空")),
  greeting      = FALSE,
  client_history = "clear"  # "clear" | "set" | "append" | "keep"
)
```

`client_history` 参数控制 ellmer Chat 的 turns，比我们的 `/clear` 更灵活。

---

## `allow_attachments = TRUE` in `chat_ui()` ✅ 已集成

```r
# R/ui_panels.R — 已在 codeagent 中启用
shinychat::chat_ui("chat", fill = TRUE, allow_attachments = TRUE, ...)
```

附件通过 `user_input_contents()` 解析后传给 LLM。

## `user_input_contents(value)` ✅ 已集成

```r
# R/server_chat.R — 已在 codeagent 中使用（内部函数）
contents <- shinychat:::user_input_contents(input$chat_user_input)
# 返回 character（纯文本）或 list（text + ContentImage/ContentPDF 等）
```

## `chat_attachment(path, mime, name)`

程序化创建附件。未在 codeagent 中使用（用户通过 UI 上传）。
潜在用途：IDE addin 把当前编辑文件作为附件注入对话。

## `ContentSlashCommand` S7 类

继承自 `ContentText`，构造器：`ContentSlashCommand(text, command, user_text)`。
由 `chat_server()` 内部在 slash handler 调用时创建，`@user_text` 是 `/cmd` 后的参数。

## `chat_enable_history` / `ConversationStore` / `FileConversationStore`

codeagent **不使用**（有自己的 sessions.R JSONL 系统，功能更完整：
fork/tag/rename/lossless tool call 保真）。

## `history_options(restore_mode, store, scope, title, max_store_mb)`

配合 `chat_enable_history()` 使用，codeagent 不用。

---

## 已在 CRAN 0.4.0 存在（不是新功能）

- `chat_ui(fill=, enable_cancel=, ...)`
- `chat_append()`, `chat_append_message()`
- `contents_shinychat()` — codeagent 用于历史 replay
- `chat_greeting()`, `chat_set_greeting()`, `chat_get_greeting()`
- `chat_restore()` — bookmark 恢复（0.3.0）
- `output_markdown_stream()`, `markdown_stream()`
