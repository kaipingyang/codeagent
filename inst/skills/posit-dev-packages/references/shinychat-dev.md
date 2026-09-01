# shinychat 当前 GitHub HEAD API 审计

当前安装：`0.4.0.9000`

仓库：`posit-dev/shinychat`，R package subdir：`pkg-r`

完整 SHA：`2b249764ce45b224224b7d185b3f34f14d0ad84f`

最后验证：2026-08-31

该构建共有 **33 个 exports、32 个 Rd topics、0 个未文档化 export**。开发版
`Version` 不唯一标识构建；核验时必须同时检查完整 `RemoteSha` 和
`RemoteSubdir = "pkg-r"`。

## 安装

```r
pak::pak(
  "posit-dev/shinychat/pkg-r@2b249764ce45b224224b7d185b3f34f14d0ad84f"
)
```

## `page_chat()` 全参数契约及 codeagent 决策

`page_chat()` 是唯一顶层 page，拥有 full-window sizing、单个持久 chat root、
responsive app menu、`height/fill/show_history`。codeagent 不在外层再包 page，也不把
这三个 page-owned 参数塞进 `...`。

| 参数 | 当前取值/处理 | 决策依据 |
|---|---|---|
| `title` | `"codeagent"` | page shell 与默认 window title |
| `icon` | `NULL` | 当前无产品图标，不伪造 |
| `...` | 传入共享 chat 参数及 `aside-favicon="false"` | 只传 `chat_ui()` 支持的参数/HTML attribute |
| `id` | `"chat"` | 与 server input、drawer API、replay 一致；page root 派生为 `chat_page` |
| `pages_navbar` | `NULL` | 当前没有真正 secondary product page |
| `toolbar` | `NULL` | 没有仅 home page 可见的 action |
| `toolbar_global` | dark mode + Workspace | `bslib::toolbar()` + 官方 `toolbar_input_button()`；desktop/mobile 移动时 ID 不复制 |
| `toolbar_input` | `NULL` | model/settings 属于 sidebar；交互 UI 与 skill footer 使用 `footer` |
| `navbar_options` | 默认 | 无定制 title bar、position 或 collapsible 需求 |
| `sidebar` | codeagent `bslib::sidebar()` | 官方支持；承载自有 Sessions/model/permission/tool controls |
| `messages` | `NULL` | 初始/恢复消息由 greeting 与 lossless replay 管理 |
| `greeting` | persistent codeagent greeting | New/Delete/Load 通过 `chat_clear(greeting=TRUE)` 重启 lifecycle |
| `placeholder` | codeagent 文案 | 告知 `/` skills 与 ESC interrupt |
| `width` | **`"100%"`** | 主 chat 跟随可用 main column；sidebar/drawer 仍缩小 containing width，不继承 760px prose cap |
| `icon_assistant` | `NULL` | 接受 HEAD 新默认：不显示 assistant robot icon |
| `icon_send` | `NULL` | 使用官方默认 ready-state arrow 与 state styling |
| `enable_cancel` | `TRUE` | 手工 observer 处理 `input$chat_cancel` 并取消 ellmer controller |
| `allow_attachments` | `TRUE` | 输入稳定为 ellmer `Content` list，并完整进入 input gate/stream splice |
| `footer` | interaction UI + skill footer | 需要 bottom-pinned full-width 区域 |
| `drawer` | `chat_drawer(Output/Files/File, width="50%", open=TRUE, resizable=TRUE)` | artifact workspace，而非 secondary page |
| `window_title` | `NA` 默认 | 从 `title` 派生即可 |
| `lang` | `NULL` | 不错误硬编码 `en`；交由宿主/浏览器语言 |
| `theme` | `.resolve_page_chat_theme()` | 所有主题从 `page_chat_theme()` 基线创建 |

当前没有独立 About/Settings 等 secondary product page，因此不采用
`chat_nav_panel()` 不是遗漏。未来确有完整页面时再用 `pages_navbar`，通过
`input$chat_page`（home 值为 `"__home__"`）和 `nav_select/show/hide()` 导航；当前
HEAD 仍不支持 `nav_insert()/nav_remove()`。

## `chat_ui()` 全参数契约及 codeagent 决策

共享参数由 `.codeagent_chat_args()` 生成；classic 直接调用 `chat_ui()`，page_chat
则由 `page_chat()` 创建唯一 chat root。

| 参数 | classic | page_chat | 决策/语义 |
|---|---|---|---|
| `id` | `"chat"` | `"chat"` | server contract 唯一 ID |
| `...` | `aside-favicon="false"` | 同左 | 防第三方 favicon 请求 |
| `messages` | `NULL` | `NULL` | 使用 greeting/replay，不维护第二份初始消息 |
| `greeting` | persistent greeting | 同左 | 不使用已更名的 `dismissible` |
| `placeholder` | codeagent 文案 | 同左 | 产品提示文案 |
| `width` | 保留 HEAD 默认 `min(clamp(680px, 50vw, 760px), 100%)` | **`100%`** | embedded prose chat 与 full-window main column 分开处理 |
| `height` | 默认 `"auto"` | page-owned | 不破坏 fill-sensitive 父布局 |
| `fill` | `TRUE` | page-owned | classic 位于真正 fillable card；page 不重复传 |
| `icon_assistant` | `NULL` | `NULL` | HEAD 默认无 assistant icon |
| `icon_send` | `NULL` | `NULL` | 无需自定义 glyph/CSS |
| `enable_cancel` | `TRUE` | `TRUE` | codeagent 自己 wiring cancellation |
| `submit_key` | `chat_submit_key` | 同左 | 完整支持 `enter` 与 `enter+modifier` |
| `allow_attachments` | `TRUE` | `TRUE` | 恒接收 `Content` list；`do.call(stream_async, ...)` 等价于文档的 `!!!` splice |
| `toolbar_input` | `NULL` | `NULL` | 当前 controls 不属于 composer 下方 input toolbar |
| `footer` | interaction + skills | 同左 | approval/question/skill actions |
| `drawer` | **`FALSE`** | page-owned显式 workspace drawer | classic 已有右侧 panel；第二轮审核移除其空默认 drawer |
| `show_history` | **`FALSE`** | page-owned | codeagent Sessions 独占 history；第二轮审核移除 classic 的原生 presentation |
| `tool_grouping` | `"tool"` | `"tool"` | 同工具在连续 tool loop 中聚合；prose/thinking 自动断组 |

补充运行时语义：

- `allow_attachments=TRUE` 时 `input$chat_user_input` **总是** ellmer `Content` list，
  即使只有文本；当前 observer 仅为旧 wire payload 保留窄兼容分支，随后按位置 splice。
- 该 input 在 HEAD 中是持久 regular input，不再提交后重置为 `NULL`；codeagent 依赖
  Shiny 的提交 event 触发，不假设读取后清空。
- `stream="content"` 保留 `ContentThinking`、tool calls 与 attachments；raw
  `<thinking>`/`<topic>` 也由 shinychat renderer 自动处理。
- shinychat 原生 streaming 状态允许继续编辑、只阻止再次提交。codeagent 的手工
  agent loop 还会在 streaming/local command/initialization 期间锁定 composer，且
  server 端再次拒绝 overlapping turn；这是并发 harness ownership 决策，不是参数遗漏。
- 不覆盖全局 `options(shinychat.tool_display=)`；因此尊重宿主的 `"none"`、`"basic"`
  或 `"rich"` 选择，默认 rich 时使用官方 compact/framed display。

## Vignette、官方 example 与 NEWS 二轮审核

已逐节核对 exact HEAD 的 `get-started.Rmd`、`articles/tool-ui.Rmd`，并全文核对
`page-chat-navigation`、`page-chat-drawer-controls` 两个安装示例及 development NEWS：

- `page_chat()` 不可再包另一 page container；当前结构符合。
- `toolbar_global` 控件会在 desktop/mobile 位置间移动，必须保持单一 input ID；当前
  dark mode 与 Workspace 均只挂载一次，Workspace 使用官方 `toolbar_input_button()`。
- drawer 可承载 live Shiny bindings，适合当前 Output/Files/File workspace；四个
  drawer server API 均由统一 helper 覆盖。
- 手工 custom loop 应使用 `stream_async(..., stream="content")`、自己管理 cancel
  controller，并 splice attachments；当前路径全部符合。
- development NEWS 新的 wider large-display 默认仅适合 embedded `chat_ui()`；
  full-window page_chat 显式 `width="100%"`，classic 保留上游默认。
- `tool-ui.Rmd` 尚有一处过时文字 `presentation="framed"`；exact HEAD 的真实 formals
  与 Rd 均为 `tool_result_display(open_style="framed")`，codeagent 正确采用后者。
- NEWS 的 CSS prefix breaking change 与 title tense change未命中 codeagent 自定义
  selector/自动 tense 逻辑；输入 attachment shape、persistent input、默认无 assistant
  icon、`tool_grouping`、cancel 与 greeting race 均已在实现或上述决策中覆盖。

## 33 个公开 API 的逐项状态

| Export | 官方用途 | codeagent 状态与位置 |
|---|---|---|
| `chat_app()` | `page_chat()` + `chat_server()` 的单用户完整 app | **不采用**；codeagent 需要 per-session client、权限、hooks、Data Shield 和自有 agent loop |
| `chat_append()` | 追加完整/流式 assistant 或 user message | **采用**：`R/server_chat.R`、local command feedback |
| `chat_append_message()` | 低层 chunk start/append/replace/end | **采用**：session replay 与 interaction progress |
| `chat_attachment()` | 本地文件编码为 composer attachment | **采用**：Files viewer 的 “Attach to chat” |
| `chat_clear()` | 清空 UI；`greeting=TRUE` 重启 greeting lifecycle | **采用**：New/Delete/Load 统一先 `greeting=TRUE` |
| `chat_drawer()` | drawer 初始内容/标题/宽度/状态 | **采用**：Output/Files/File workspace |
| `chat_drawer_hide()` | 隐藏 drawer | **通过统一 wrapper 支持**：`.shinychat_drawer_action()` |
| `chat_drawer_show()` | 可更新内容/标题后显示 | **采用**：tool result、file selection 自动打开 |
| `chat_drawer_toggle()` | 切换 drawer 可见性 | **采用**：persistent Workspace toolbar button |
| `chat_drawer_update()` | 更新内容/标题且不改变可见性 | **通过统一 wrapper 支持**；当前 reactive outputs 无需手动更新内容 |
| `chat_enable_history()` | 多会话 history controller | **不采用**；会与 codeagent JSONL session、hooks 和 replay 双写 |
| `chat_get_greeting()` | 查询当前 greeting | **暂不需要**；codeagent reset 流程不依赖 client round-trip 查询 |
| `chat_greeting()` | static/dynamic greeting 配置 | **采用**：persistent codeagent greeting |
| `chat_mod_server()` | 旧 module server | **不采用**；官方已 deprecated |
| `chat_mod_ui()` | 旧 module UI | **不采用**；官方已 deprecated |
| `chat_nav_panel()` | page_chat secondary page | **当前不采用**；workspace 是 artifact drawer，不是独立导航页 |
| `chat_restore()` | 单会话 Shiny bookmarking | **不采用**；与 codeagent provider-preserving session restore 冲突 |
| `chat_server()` | batteries-included stream/history/slash/client owner | **不采用**；会注册第二个 input observer并绕过 permission、compaction、hooks、Data Shield |
| `chat_set_greeting()` | server 设置/流式/清除 greeting | **采用**：reset 后设置 persistent greeting |
| `chat_sidebar()` | page_chat sidebar + optional native history | **不直接采用**；官方同样允许的 `bslib::sidebar()` 更适合现有 controls，history 明确由 codeagent 管理 |
| `chat_ui()` | embedded chat root | **采用**：classic layout；`page_chat()` 内部拥有 page_chat root |
| `chat_ui_history()` | 独立原生 history selector | **不采用**；codeagent 有自己的 Sessions UI/schema |
| `contents_shinychat()` | ellmer Content 到原生 chat UI | **采用**：lossless turn replay 与 tool card presentation |
| `ContentSlashCommand()` | provider 看展开 text、replay 看原始 `/command args` | **采用**：skill prompt 在 Data Shield 和 reminder 后包装 |
| `ConversationStore` | history backend 抽象 R6 | **不采用**；现有 codeagent append-only JSONL 与 mutation API |
| `FileConversationStore` | shinychat 文件 history backend | **不采用**；无跨进程协调且 schema 与 codeagent session 不同 |
| `history_options()` | history store/scope/title/restore 配置 | **不采用**；同上 |
| `markdown_stream()` | chat 外 markdown streaming | **不用于主聊天**；`chat_append()` 才是聊天路径 |
| `output_markdown_stream()` | chat 外 markdown stream UI | **不用于主聊天**；当前 Output panel 是 typed artifact renderer |
| `page_chat()` | full-window、单 chat root page | **采用**：`ui_layout="page_chat"` |
| `page_chat_theme()` | page_chat surface/radius/density/system-font baseline | **采用**：`.resolve_page_chat_theme()` |
| `tool_result_display()` | 官方 compact activity + drill-down display | **采用**：label/value preview、framed artifact、private metadata 留在 `extra$codeagent` |
| `update_chat_user_input()` | composer text/placeholder/submit/focus/attachments | **采用**：IDE prefill、skill picker、Files attachment staging |

## Ownership boundary

codeagent 只采用 shinychat 的 **presentation 与 client protocol**，不把 harness ownership
交给 `chat_server()`：

1. `server_chat()` 独占 `input$chat_user_input` 和 ellmer streaming；
2. permission gate、tool lifecycle、compaction、hooks、session save、citation bridge 和
   Data Shield 都包围模型边界；
3. session replay 使用 presentation-only Chat copy + `contents_shinychat()`，不改
   provider-facing turns、tool request/result IDs 或 lossless stored values；
4. skill slash command先经过 input gate和system reminder，再包装
   `ContentSlashCommand`，所以不会为了漂亮 replay 绕过安全边界。

## 关键上游行为

- `tool_result_display(open_style = "framed")` 是正确值，不是 `"frame"`。
- compact citation 使用 `<shiny-aside display="compact">`；codeagent 只允许服务器
  从当前-turn validated source registry 构造 aside，raw model tag 不进入浏览器。
- `chat_clear(greeting = TRUE)` 是已 dismissed greeting 重新出现的必要步骤。
- `update_chat_user_input(attachments=, attachment_mode="append")` 接收
  `chat_attachment()` 输出；真正提交后仍经过 codeagent Data Shield input gate。
- `page_chat()` 的 global toolbar 在 secondary pages 与 desktop/mobile layouts 间
  保持同一挂载实例，适合 dark mode 与 drawer toggle。
