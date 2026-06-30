# 换模型方案：探索记录与备选方案

> 调研日期：2026-06-30
> 状态：当前采用「路线 A 原地换 provider + 路线 B 回退」（见 roadmap.md M1）
> 本文档：完整记录所有实测数据 + 备选方案，供未来回溯/切换

---

## 背景

Claude Code 支持 `settings.json` 配置模型 + `/model` 命令会话中换模型。
codeagent 目标对齐：会话中无损切换模型（保留对话历史 + 工具调用记录）。

LLM 本身无状态，对话历史在 harness 侧（ellmer `Chat` 对象的 turns）。
换模型 = 换 provider/model，迁移历史。

---

## 实测数据（13 点，全部跑过验证）

### A. ellmer 迁移能力

| # | 验证 | 结果 |
|---|------|------|
| 1 | 裸 `set_turns` 迁移 | 内存内无损，但 **JSON 序列化有损/失败** |
| 2 | `contents_record/replay` | **JSON 可序列化**（存盘/跨进程安全）|
| 3 | 嵌套 args + error result 跨 provider | openai↔anthropic 完全无损 |
| 4 | `set_turns` 迁移范围 | 只迁 turns，**不**迁 system_prompt/tools |
| 5 | ellmer 有无 `set_model` | **无**；但 `provider@model` 是 S7 可变 slot |
| 6 | `get_provider()` 返回 | **副本**（改副本不回写 chat）|
| 7 | 改私有 `private$provider@model` | ✅ 同 provider 原地换 model，turns 不动 |
| 8 | 原地换整个 `private$provider` | ✅ **跨 provider，turns+tools+sp 全保留，零重建** |

### B. codeagent 现状

| # | 验证 | 结果 |
|---|------|------|
| 9 | `.make_chat(settings)` | 内置 chat 工厂（从 settings$model 建）|
| 10 | `codeagent_client(new_chat)` 重建 | turns 留、sp 重注入、51 tools 重注册、model 更新 |
| 11 | `server_sessions.R` 换历史先例 | **已用 `chat$set_turns()`** 原地换历史（换模型先例）|
| 12 | chat 闭包捕获 | chat 被 5 个 server 模块函数参数闭包捕获 |
| 13 | `stream_controller` 绑定 | **独立对象**，`stream_async(controller=)` 传入，不绑 chat/provider |

### 关键代码片段（实测可跑）

```r
# 路线A 核心: 原地换 provider，turns/tools/sp 全保留
ch <- chat_openai_compatible(base_url=, model="m1", credentials=, system_prompt="SP")
ch$register_tool(wt); ch$set_turns(history)
new_prov <- chat_anthropic(model="claude-sonnet-4-6")$get_provider()
ch$.__enclos_env__$private$provider <- new_prov
# → get_model()="claude-sonnet-4-6", turns/tools/system_prompt 全在

# 裸 turns JSON 有损 vs record/replay 安全
jsonlite::serializeJSON(ch$get_turns())            # 有损/失败
lapply(ch$get_turns(), ellmer::contents_record)    # JSON 安全
```

---

## 当前采用方案（路线 A + B 回退）

见 `roadmap.md` M1。要点：
- **路线 A**（默认）：原地改 R6 `private$provider`，chat 对象不变 → server 闭包零改、stream_controller 不受影响
- **路线 B**（回退）：`get_turns→新chat→set_turns→codeagent_client 重建`，纯公开 API
- `tryCatch` 包路线 A，失败回退 B

**选它的理由**：chat 对象不变是最大优势——5 个 server 模块的闭包、打断机制全部零改。

---

## 备选方案（未采用，留档）

### 备选 1：纯路线 B（公开 API 重建，不碰私有）

**做法**：每次换模型都 `get_turns → .make_chat → set_turns → codeagent_client 重建`，返回**新 client 对象**。

**优点**：
- 只用公开 API（`get_turns/set_turns/.make_chat/codeagent_client`），ellmer 升级不破
- 逻辑直白，无私有内部依赖

**缺点**：
- 新 chat 对象 → server_chat 等 5 模块闭包捕获旧 chat，**Shiny 必须把 chat 改 reactive 间接引用**
- stream_controller 在闭包里，新 chat 后需重新接线
- 重建开销（重注册 51 tools + 重建 system prompt）每次都跑

**何时切换到此**：若 ellmer 未来把 `.__enclos_env__$private` 锁死，路线 A 失效，全量回退此方案。

### 备选 2：thunk 工厂模式（参考 shinyAssistantUI/shinyAntDesignX）

**做法**：`codeagent_client(chat = function(model) ...)` 接 thunk 而非 chat 对象，
配 `current` env 回调转发（回调注册一次在 chat 上，行为通过可变 `current` env 切换）。

**优点**：
- `current` env 技巧能破闭包捕获死结——回调注册一次，换 chat 时只换 `current` 内容
- 参考项目验证过的模式（虽然它们没真做换模型）

**缺点**：
- codeagent 现有 API 是 `codeagent_client(chat=对象)`，改成 thunk 是**破坏性 API 变更**
- 引入 thread_id 字典等 codeagent 不需要的多路复用复杂度（codeagent 单会话）
- 工程量大（重构 handler）

**何时考虑**：若 codeagent 未来要支持**多并发会话**（thread），thunk + thread 字典才有价值。当前单会话不需要。

### 备选 3：同 provider only（最保守）

**做法**：只支持同 provider 换 model（openai m1→m2），用 `private$provider@model <- "m2"` 改单字段（实测数据点 7）。跨 provider 不支持。

**优点**：改动最小（一个 slot 赋值），私有 API 依赖最浅

**缺点**：功能受限——不能 openai→anthropic。多数换模型场景恰恰是跨 provider（换厂商/换能力档位）

**何时用**：若只需在同一 base_url 下切换 model 档位（如 databricks 的 gpt41→gpt4o），此方案够用且最稳。

---

## 决策矩阵

| 方案 | API 稳定性 | Shiny 改动 | 跨 provider | 重建开销 | 采用 |
|------|-----------|-----------|------------|---------|------|
| 路线A 原地换 provider | 私有(脆) | 零 | ✅ | 零 | **✅ 当前** |
| 路线B 公开重建 | 公开(稳) | 大(reactive 化) | ✅ | 每次 | 回退 |
| thunk 工厂 | 破坏性变更 | 大(重构) | ✅ | 中 | 多会话时 |
| 同 provider only | 私有(浅) | 零 | ❌ | 零 | 受限场景 |

**当前组合 = 路线A（默认）+ 路线B（tryCatch 回退）**：兼顾零 Shiny 改动 + API 失效兜底。

---

## 风险与监控

1. **ellmer 私有 API 变动**：`.__enclos_env__$private$provider` 是内部结构，ellmer 升级可能改。
   - 缓解：`tryCatch` 回退路线 B；加版本检测；测试覆盖
2. **provider 不兼容工具格式**：已验证 openai↔anthropic；ollama/google 等需上线前测
3. **prompt cache 失效**：换 model 必然，无解，历史无损可接受
4. **流式中切换**：禁止（`stream_task$status()=="running"` 拦截）

---

## 参考

- `roadmap.md` M1 — 当前方案实施计划
- ellmer `contents_record` / `contents_replay` / `set_turns` / `get_provider`
- shinyAssistantUI/shinyAntDesignX `R/ellmer_store.R`（record/replay 持久化模式，两项目相同）
