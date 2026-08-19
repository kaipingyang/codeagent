# shinychat 开发版新功能（vs CRAN 0.4.0）

当前安装：`0.4.0.9000`（GitHub: `posit-dev/shinychat/pkg-r`）
当前 SHA：`aa35a0988319103c35637e6d467ebc02a3180e3c`
最后验证：2026-08-18

## 安装路径

shinychat 是 monorepo，R 包位于 `pkg-r`：

```r
pak::pak("posit-dev/shinychat/pkg-r")
```

不能安装 `posit-dev/shinychat` 仓库根目录；安装后的 `RemoteSubdir` 应为 `pkg-r`。

## 当前开发版重点功能

### Web search、fetch 和 citation UI（#280）

shinychat 现在能直接渲染 ellmer 的 web activity 和 `ContentCitation`：

- web search/fetch 显示为紧凑活动 UI；
- citation pill 显示在其支持的 claim 旁；
- `grounded_span` 将引用与回答文本关联，打开引用时高亮对应文字；
- message-wide Sources 汇总每个来源 URL；
- Markdown 强调边界和重复引用均可正确处理；
- 同一 aside 组件也可用于自定义 RAG 来源。

### Aside 渲染和响应式修复

- Markdown 列表项中的 `<shiny-aside>` 不再破坏列表结构、富文本 body、footnote 或 reference definition（#305）。
- standalone aside 的长标签会截断，popover 标题限制为两行，内容区域独立滚动，并在窄屏/200% 字体下保持在 viewport 内（#308）。

这些变更更新了随 R 包分发的 JavaScript/CSS assets，因此 codeagent 使用 `chat_ui()` 时可直接受益。

### Conversation history 防御与 greeting 修复

- R/Python 两端现在严格校验 conversation record 的 `schema_version`；当前只接受版本 1，缺失版本按 1 兼容处理。拒绝不支持版本时不会修改原文件（#313）。
- 修复 greeting 与异步 history restore 的竞态：恢复旧会话时不再短暂闪现 greeting，从恢复会话新建聊天时 greeting 也能重新出现（#275）。
- 补充 `chat_ui()`/`chat_server()` 按相同 `id` 配对的文档（#300）。
- 补充 `FileConversationStore` 的 `list/get/put/delete` R6 方法文档（#301）。

codeagent 使用自己的 JSONL session 系统而非 shinychat conversation history，因此这些 history 修复目前不是直接运行路径。

## 其他开发版 API

### `chat_server()`

`chat_server()` 是新的主要 server API，与 `chat_ui()` 通过相同 `id` 配对，不需要在顶层额外使用 `NS()`。它提供 streaming、client 切换、slash commands、attachments 和多会话 history。

codeagent **不调用** `shinychat::chat_server()`：`R/ui.R` 和 `R/server_chat.R` 自己管理 agent loop、权限、skills、compaction、hooks、Data Shield 和 session 保存。若同时注册 `chat_server()`，会产生两条 input observer 和重复 streaming。

### Attachments 和 slash commands

- `chat_ui(allow_attachments = TRUE)` 支持图片、PDF 和文本附件；
- `user_input_contents()` 将输入规范化为文本或 ellmer Content 列表；
- 原生 slash palette 可注册带参数的 `ContentSlashCommand`；
- `contents_shinychat()` 可把 ellmer turns 还原成文本、thinking 和 tool cards。

## codeagent 当前集成

| shinychat 能力 | codeagent 使用位置 |
|---|---|
| `chat_ui(..., allow_attachments = TRUE)` | `R/ui_panels.R` |
| `user_input_contents()` | `R/server_chat.R` |
| `chat_append()` + ellmer content stream | `R/server_chat.R` |
| `contents_shinychat()` | `R/server_sessions.R` 历史 replay |
| slash palette | `R/server_slash.R`，不依赖 `chat_server()` |

### codeagent 已落地的 shinychat 集成

#### 确定性 citation bridge

codeagent 的 WebSearch/WebFetch 仍是自定义工具，但不再依赖模型直接生成 `<shiny-aside>`。工具保存当前-turn
source records，模型仅输出 `[[cite:SOURCE_ID|visible claim]]`；服务器验证、扫描并从 registry 确定性重建
固定 allowlist aside。citation mode 在有无 Data Shield 时都 buffer-then-show，未知/跨轮/畸形 marker 安全降级。
真实 Chromium 已验证 inline pill、grounded span、Sources、safe href，且 raw model aside 不进入 DOM。

#### 官方 tool display 与 replay

`.tool_result2()` 使用 feature-detected `shinychat::tool_result_display()`，包含 compact `label`、
`value_preview`、footer，同时把 artifact/source metadata 留在 `extra$codeagent`。旧 session 的
`display$toolcard/right_output` 只在 presentation Chat copy 上迁移，不改变 provider-facing value、tool IDs 或顺序。

#### persistent greeting

`chat_ui()` 使用 `chat_greeting(..., persistent=TRUE)`；New/Delete/Restore 后重新设置 greeting，但恢复历史时不重复。
`codeagent_app(greeting=)` 仍保持 composer prefill 语义，不与 persistent greeting 混用。

上游比较：<https://github.com/posit-dev/shinychat/compare/be8b827c2238055650e63748ccd36860a2b99361...aa35a0988319103c35637e6d467ebc02a3180e3c>
