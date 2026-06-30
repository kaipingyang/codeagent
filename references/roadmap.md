# codeagent Roadmap

> 制定日期：2026-06-30
> 依据：Claude Code 概念图审计（9✅/11🟡/0❌）+ 换模型 13 点实测 + Rapp CLI 能力对比 + 五问结论

---

## 北极星

codeagent = R-native Claude Code harness。目标对齐 Claude Code 概念图五层，
**harness 逻辑纯 R 无 shiny 依赖**，CLI 和 Shiny 都是薄壳调同一套 harness 函数。

---

## 工程化总原则（贯穿所有阶段）

1. **harness 层纯函数**：换模型、session、compaction、permission 等核心逻辑放 `R/*.R`，零 `shiny::` 依赖。CLI（`exec/codeagent.R`）和 Shiny（`server_*.R`）都是薄壳。
2. **Shiny 状态**：单个 `reactiveValues()`（`ui.R` 的 `state`），禁止散落 `reactiveVal`。可变跨模块状态（如 active client）加 slot 到 `state`。
3. **公开 API 优先 + 私有 API 回退**：碰 ellmer `.__enclos_env__$private` 必须 `tryCatch` + 回退公开 API 路径。
4. **改代码同步测试 + example**（CLAUDE.md 既有规则）。
5. **双适配验证**：每个 harness 功能必须 CLI + Shiny 两条路径都测。

---

## 阶段总览

| 阶段 | 主题 | 优先级 | 依赖 | 成本 |
|------|------|--------|------|------|
| **M1** | 换模型核心（harness 纯函数）| P0 | 无 | 低 |
| **M2** | Shiny 换模型集成 | P0 | M1 | 低 |
| **M3** | CLI 补强（--model / --continue / 流式）| P1 | M1 + sessions | 中 |
| **M4** | CLI 交互式 REPL | P2 | M3 | 中高 |
| **M5** | 概念图缺口：Hook 事件扩展 | P1 | 无 | 中 |
| **M6** | 概念图缺口：auto-memory | P2 | 无 | 中 |
| **M7** | session 持久化升级（record/replay）| P2 | 无 | 低 |
| **M8** | 概念图缺口：MCP 多 transport / sandbox | P3 | 无 | 高 |

---

## M1：换模型核心（harness 纯函数）— P0

**新文件 `R/model_switch.R`（纯 R，无 shiny）**

```r
switch_model(client, model)        # 主入口，CLI+Shiny 共用
.swap_provider(chat, new_provider) # 路线A: 原地换 R6 private$provider
.resolve_model_spec(model)         # 复用 client_config alias 解析
```

**实测依据（已验证）**：
- 路线 A（原地换 provider）：turns+tools+sp 全保留，chat 对象不变 → server 闭包零改、stream_controller 不受影响
- 路线 B（回退）：`get_turns→新chat→set_turns→codeagent_client 重建`，纯公开 API
- 跨 provider（openai↔anthropic）含嵌套 args/error result 迁移无损

**设计**：
```r
switch_model <- function(client, model) {
  spec  <- .resolve_model_spec(model)
  fresh <- .make_chat(modifyList(client$settings, list(model = spec)))
  ok <- tryCatch({                                   # 路线A
    client$chat$.__enclos_env__$private$provider <- fresh$get_provider()
    TRUE
  }, error = function(e) FALSE)
  if (ok) { client$settings$model <- spec; return(client) }
  # 回退路线B（公开 API）
  turns <- client$chat$get_turns()
  fresh$set_turns(turns)
  codeagent_client(fresh, permission_mode = client$settings$permission_mode, ...)
}
```

**测试**：`test-model_switch.R` — provider swap 后 model 变 / turns 留 / tools 留 / sp 留 / 跨 provider / 回退路径触发 / 流式中拒绝切换。

**交付**：harness 函数 + 测试。CLI/Shiny 未接。

---

## M2：Shiny 换模型集成 — P0

- `ui.R`：`state` 加 slot `client`（reactiveValues，符合规则）；初始 `state$client <- ca_client`
- 5 个 server 模块改读 `state$client$chat`（路线 A 下 chat 对象不变，多数无需改；只 `state$client` 引用更新）
- `server_settings.R`：Settings 面板加 model selectInput（alias 列表来自 `codeagent.md`）+ observer：
  ```r
  observeEvent(input$model_select, {
    if (stream_task$status() == "running") { show_toast("流式中，无法切换"); return() }
    state$client <- switch_model(state$client, input$model_select)
    bslib::show_toast(sprintf("切换到 %s，历史已保留", input$model_select))
  })
  ```
- 用 `bslib::show_toast`（既有组件规则）

**测试**：app 启动 + 模拟 model_select observer。

---

## M3：CLI 补强 — P1

`exec/codeagent.R` 扩展：
- `run --model anthropic/claude-...`：调 `switch_model` 或建新 client
- `run --continue` / `--resume <id>`：复用现有 JSONL session（`read_session` + `set_turns`），CLI 续聊
- `run` 流式输出：当前阻塞返回 → 改 `stream_async` + 逐 chunk `cat`

**差距填补**：session 续聊（JSONL 已有，CLI 没接）、流式。

---

## M4：CLI 交互式 REPL — P2

**最大 CLI 差距**。Rapp 是子命令式（非 REPL 框架），需自写：
- `codeagent repl` 子命令：`readline` loop + 流式 + `/model` `/compact` `/skill` 斜杠命令
- Ctrl-C 打断（`stream_controller` 复用）
- 权限交互确认（`.console_ask_fn` 已有）

**结构性限制**：给不了 Claude Code 的 ink/React 终端 UI，只能纯文本 REPL。

---

## M5：Hook 事件扩展 — P1

概念图最大缺口（7/27）。当前 `HookEvent$*` 7 个，补关键缺失：
- `SessionStart` / `Stop`（会话生命周期）
- `PreCompact`（compaction 前，已有 5 层 compaction 可挂）
- `SubagentStart` / `SubagentStop`（子 agent 生命周期）
- `UserPromptSubmit`（已有 UserMessage，可能重命名对齐）

**价值**：扩展性底座，PreCompact/Subagent hooks 是其他功能依赖。

---

## M6：auto-memory — P2

概念图 State 层缺失。Claude Code 的 auto-memory：agent 自主写记忆到 `~/.codeagent/memory/`，下次会话注入。
- `memory.R`：read/write/recall
- 注入点：`.build_system_reminder` 或 system prompt
- CLAUDE.md 四级层次对齐（Enterprise>Project>User>Auto）

---

## M7：session 持久化升级 — P2

**实测发现**：`server_sessions.R` 用裸 `set_turns`，内存 ok 但 **JSON 序列化有损**。
- 升级为 `ellmer::contents_record()` / `contents_replay(tools=)`（JSON 安全，跨进程）
- 参考 shinyAssistantUI/shinyAntDesignX 的 `.ellmer_chat_get_state/set_state` 模式（gzip+base64）
- 影响：session 存盘真无损 + CLI `--resume` 可靠

---

## M8：MCP 多 transport / sandbox — P3

- MCP client：当前只 btw http，补 stdio/SSE/WebSocket
- sandbox：Bash/RunR 的 fs/network 隔离（R 侧复杂，可选）

---

## 概念图覆盖目标

| 阶段后 | ✅ | 🟡 | ❌ |
|--------|-----|-----|-----|
| 现状 | 9 | 11 | 0 |
| M1-M2 后 | +换模型 | | |
| M5 后 | +Hook(27) | | |
| M6-M7 后 | +auto-memory +持久化 | | |

---

## 推荐执行顺序

1. **M1 → M2**（换模型，P0，你的主诉求，低成本，已验证）
2. **M3**（CLI --model/--continue，复用 M1 + 已有 session）
3. **M5**（Hook 扩展，扩展性底座）
4. **M7**（持久化升级，低成本，修实测发现的有损 bug）
5. **M4 / M6 / M8**（REPL / auto-memory / MCP-sandbox，按需）

**第一步**：M1 `R/model_switch.R` 纯函数 + 测试。
