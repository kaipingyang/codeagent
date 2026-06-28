# Claude Code 完整概念图

> 来源：arXiv 2604.14228 + 官方文档 + 逆向分析
> 日期：2026-06-28

---

## 全局架构（五层）

```
┌─────────────────────────────────────────────────────────────────────┐
│                        SURFACE LAYER 入口层                          │
│   Interactive CLI   │   Headless CLI   │   SDK   │   IDE/Browser     │
│   (ink terminal UI) │   (单次执行)      │(事件流) │   (嵌入式)         │
└────────────────────────────────┬────────────────────────────────────┘
                                 │
┌────────────────────────────────▼────────────────────────────────────┐
│                        CORE LAYER 核心层                             │
│                                                                     │
│   ┌──────────────────── HARNESS ─────────────────────────────────┐  │
│   │                                                              │  │
│   │   Context Assembly（上下文组装）                              │  │
│   │   ┌──────────┬────────────────┬──────────────────────────┐  │  │
│   │   │ System   │  CLAUDE.md     │  <system-reminder>       │  │  │
│   │   │ Prompt   │  四级层次结构   │  (动态注入，不破坏cache)  │  │  │
│   │   │ (共享缓存)│ proj/user/glob │                          │  │  │
│   │   └──────────┴────────────────┴──────────────────────────┘  │  │
│   │                          │                                   │  │
│   │                          ▼                                   │  │
│   │   ┌─────────────── AGENT LOOP (queryLoop) ────────────────┐  │  │
│   │   │                                                       │  │  │
│   │   │   1. Settings Resolution                              │  │  │
│   │   │   2. Mutable State Init                               │  │  │
│   │   │   3. Context Assembly ──→ getSystemContext()          │  │  │
│   │   │                          getUserContext()             │  │  │
│   │   │   4. Pre-model Shapers（前置处理器）                   │  │  │
│   │   │         │                                             │  │  │
│   │   │         ▼                                             │  │  │
│   │   │   5. ┌─────────────────────────────────────────┐     │  │  │
│   │   │      │           MODEL CALL（LLM）               │     │  │  │
│   │   │      │  ANTML Tags：                            │     │  │  │
│   │   │      │  <thinking> 思维链                       │     │  │  │
│   │   │      │  <thinking_mode>interleaved              │     │  │  │
│   │   │      │  <max_thinking_length>N                  │     │  │  │
│   │   │      │  <function_calls> 工具调用               │     │  │  │
│   │   │      │  <cite> 引用                             │     │  │  │
│   │   │      └─────────────────────────────────────────┘     │  │  │
│   │   │         │                                             │  │  │
│   │   │         ▼                                             │  │  │
│   │   │   6. Tool-use Dispatch                                │  │  │
│   │   │         │                                             │  │  │
│   │   │         ▼                                             │  │  │
│   │   │   7. Stop Conditions 终止判断：                       │  │  │
│   │   │      • 无工具调用（纯文本回复）                        │  │  │
│   │   │      • Max turns 超限                                 │  │  │
│   │   │      • Context overflow                              │  │  │
│   │   │      • Hook 中断                                      │  │  │
│   │   │      • Abort signal                                   │  │  │
│   │   │                                                       │  │  │
│   │   └───────────────────────────────────────────────────────┘  │  │
│   │                                                              │  │
│   │   Compaction Pipeline（五层上下文压缩）                       │  │
│   │   ┌────────┬──────┬────────────┬──────────────┬───────────┐  │  │
│   │   │Budget  │Snip  │Microcompact│Context       │Auto-      │  │  │
│   │   │Reduce  │时间轴│缓存开销    │Collapse      │compact    │  │  │
│   │   │单消息  │裁剪  │压缩        │读时投影      │模型摘要   │  │  │
│   │   └────────┴──────┴────────────┴──────────────┴───────────┘  │  │
│   │                                                              │  │
│   └──────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
                                 │
┌────────────────────────────────▼────────────────────────────────────┐
│                     SAFETY/ACTION LAYER 安全执行层                   │
│                                                                     │
│  ┌──────── PERMISSION SYSTEM（七模式权限系统）─────────────────────┐  │
│  │                                                                 │  │
│  │  Authorization Pipeline:                                        │  │
│  │  Tool Request                                                   │  │
│  │      → Pre-filtering（deny-rule 剥离）                          │  │
│  │      → PreToolUse Hooks                                         │  │
│  │      → Rule Evaluation（deny-first 优先）                       │  │
│  │      → Permission Handler（四路由）                             │  │
│  │      → Shell Sandbox Enforcement                                │  │
│  │                                                                 │  │
│  │  七种模式：plan | default | acceptEdits | auto |                │  │
│  │           dontAsk | bypassPermissions | bubble                  │  │
│  │                                                                 │  │
│  │  Auto-mode ML Classifier：                                      │  │
│  │    yoloClassifier → fast-filter → chain-of-thought             │  │
│  └─────────────────────────────────────────────────────────────────┘  │
│                                                                     │
│  ┌──────── HOOK SYSTEM（27种生命周期钩子）────────────────────────┐  │
│  │  PreToolUse        PostToolUse       PostToolUseFailure         │  │
│  │  PermissionDenied  PermissionRequest + 22种其他事件             │  │
│  │  → shell 命令执行，不消耗 context window                        │  │
│  │  → 可以 block/modify/inject 工具调用                            │  │
│  └─────────────────────────────────────────────────────────────────┘  │
│                                                                     │
│  ┌──────── TOOL POOL（54个内置工具 + MCP工具）────────────────────┐  │
│  │  BashTool    FileReadTool   FileEditTool   FileCreateTool       │  │
│  │  FileDelete  GitOperations  DirectoryOps   + 42其他             │  │
│  │  19个无条件 + 35个特性开关控制                                  │  │
│  │                                                                 │  │
│  │  Tool Executor：                                                │  │
│  │    StreamingToolExecutor（并发）| runTools()（串行）            │  │
│  └─────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
                                 │
┌────────────────────────────────▼────────────────────────────────────┐
│                        STATE LAYER 状态层                            │
│                                                                     │
│  ┌──── SESSION STORAGE ────┐  ┌──── MEMORY ────────────────────┐  │
│  │ JSONL 追加式存储         │  │ CLAUDE.md 四级层次：           │  │
│  │ ~/.claude/projects/     │  │   Enterprise > Project >       │  │
│  │   {project}/{session}/  │  │   User > Auto-memory           │  │
│  │ Subagent sidechain      │  │ Auto-memory entries            │  │
│  │ Fork / Rewind / Resume  │  │ Global prompt history          │  │
│  └─────────────────────────┘  └────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
                                 │
┌────────────────────────────────▼────────────────────────────────────┐
│                      BACKEND LAYER 后端层                            │
│                                                                     │
│  ┌── EXTENSIBILITY（四种扩展机制）──────────────────────────────┐  │
│  │                                                              │  │
│  │  MCP（Model Context Protocol）                               │  │
│  │    transport: stdio | SSE | HTTP | WebSocket | SDK           │  │
│  │                                                              │  │
│  │  Skills（Agent Skills 开放标准）                              │  │
│  │    .claude/skills/{name}/SKILL.md                            │  │
│  │    Progressive Disclosure 三阶段加载                         │  │
│  │    /slash-command 手动 + 自动激活                            │  │
│  │    $ARGUMENTS 参数注入                                        │  │
│  │                                                              │  │
│  │  Hooks（27种事件，见上层）                                    │  │
│  │                                                              │  │
│  │  Plugins（捆绑组件）                                          │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                                                                     │
│  ┌── SUBAGENT DELEGATION（子 Agent）───────────────────────────┐  │
│  │  AgentTool → 独立 context window                            │  │
│  │  只返回 summary（不回传完整历史）                              │  │
│  │  Worktree isolation（独立 git worktree）                      │  │
│  │  bubble 权限模式（子 Agent 专用）                             │  │
│  │  自动 compaction at 95% capacity                             │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                                                                     │
│  ┌── EXECUTION ENVIRONMENT ────────────────────────────────────┐  │
│  │  Bash / PowerShell 执行层                                    │  │
│  │  可选沙箱（filesystem + network isolation）                   │  │
│  │  Remote execution                                            │  │
│  └──────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 核心概念关系图

```
                         用户输入
                            │
              ┌─────────────▼──────────────┐
              │     <system-reminder>       │  ← CLAUDE.md 动态注入
              │   + System Prompt（缓存）   │  ← 不破坏 prompt cache
              └─────────────┬──────────────┘
                            │
              ┌─────────────▼──────────────┐
              │        Plan Mode？          │  ← 规划后再执行
              └──────┬──────────┬──────────┘
                   Yes          No
                     │          │
              ┌──────▼──┐  ┌───▼───────────────────────────────────┐
              │ 展示计划  │  │            AGENT LOOP                 │
              │ 等待确认  │  │                                       │
              └──────────┘  │  while (not done):                   │
                            │    context = assemble()               │
                            │           │                           │
                            │    ┌──────▼──────────────────────┐   │
                            │    │   Compaction（5层）          │   │
                            │    │  超过阈值时自动压缩上下文     │   │
                            │    └──────┬──────────────────────┘   │
                            │           │                           │
                            │    response = LLM(context)            │
                            │           │                           │
                            │    if response.tool_calls:            │
                            │      for each tool_call:              │
                            │        ┌──▼──────────────────────┐   │
                            │        │  Permission Gate（7层）  │   │
                            │        │  → Hook PreToolUse       │   │
                            │        │  → Rule evaluation       │   │
                            │        │  → ML classifier         │   │
                            │        │  → Sandbox check         │   │
                            │        └──┬──────────────────────┘   │
                            │           │ 允许                      │
                            │        ┌──▼──────────────────────┐   │
                            │        │   Tool Execution         │   │
                            │        │  （并发 or 串行）          │   │
                            │        └──┬──────────────────────┘   │
                            │           │                           │
                            │        ┌──▼──────────────────────┐   │
                            │        │  Hook PostToolUse        │   │
                            │        └──┬──────────────────────┘   │
                            │           │                           │
                            │        append result to memory        │
                            │    else:                              │
                            │        return response.text ──────────┼──→ 输出
                            └───────────────────────────────────────┘

```

---

## Skills 概念细节

```
.claude/skills/
├── code-review/
│   ├── SKILL.md          ← 必须（frontmatter + body）
│   ├── scripts/          ← 可选
│   ├── references/       ← 可选
│   └── assets/           ← 可选
│
Progressive Disclosure（三阶段加载）：
  ① Startup:   只加载 name + description（~100 tokens）
  ② Activate:  加载完整 SKILL.md body（< 5000 tokens）
  ③ Execute:   按需加载 scripts/references/assets

调用方式：
  手动：/code-review foo.R    → parse_invocation() → body + $ARGUMENTS
  自动：agent 判断 task 匹配 description → 自动激活
```

---

## ANTML Tags（训练层内部标签）

```
<thinking>          ← 思维链包裹（ContentThinking）
<thinking_mode>     ← interleaved / none
<max_thinking_length> ← token 预算
<function_calls>    ← 工具调用块
<cite>              ← 引用来源（web search）
<system-reminder>   ← 动态上下文注入（messages 数组，非 system prompt）
```

---

## Harness vs Agent Loop

```
Agent Loop（6行逻辑）：
  while not done:
    response = LLM(messages)
    if tool_calls: execute(); append()
    else: return

Harness（Loop 周围的全部工程）：
  ├── Context Assembly    组装上下文
  ├── Compaction          压缩管理（5层）
  ├── Permission System   权限门控（7模式+ML）
  ├── Hook System         生命周期钩子（27种）
  ├── Tool Infrastructure 工具基础设施（54+）
  ├── Subagent            子 Agent 委派
  ├── Session Storage     会话持久化（JSONL）
  ├── Skills              可复用能力模块
  ├── MCP                 外部工具协议
  ├── Error Recovery      故障恢复（3次重试）
  └── Verification Loop   输出验证
  
  同一个模型，不同 harness → 性能差距最高 6x
```

---

## 13条设计原则

1. Deny-first，人工升级确认
2. 渐进信任（auto-approval 随会话增长）
3. 纵深防御（多层独立安全机制）
4. 外部化可编程策略（CLAUDE.md 而非硬编码）
5. 上下文作为稀缺资源（progressive management）
6. 追加式持久状态（Append-only JSONL）
7. 最小脚手架，最大运营 harness
8. 价值观优先于规则
9. 可组合多机制扩展（MCP+Skills+Hooks+Plugins）
10. 可逆性加权风险评估
11. 透明的文件配置和记忆
12. 隔离的子 Agent 边界
13. 优雅恢复与弹性

---

## smolagents 实现对照

| Claude Code 概念 | smolagents | 状态 |
|-----------------|-----------|------|
| Agent Loop | `MultiStepAgent._run_stream()` | ✅ |
| Tool Calling | `ToolCallingAgent` | ✅ |
| Code Agent | `CodeAgent` | ✅ 独创 |
| Memory | `AgentMemory` | ✅ |
| Streaming | generator-based | ✅ |
| Multi-Agent | `ManagedAgent` | ✅ |
| Planning | `planning_interval` | ✅ |
| Tool Sandbox | E2B/Docker/Modal | ✅ |
| Skills | — | ❌ |
| Hooks | — | ❌ |
| Compaction（5层）| — | ❌ |
| Permission System | — | ❌ |
| MCP Client | — | ❌ |
| Session Storage | — | ❌ |
| system-reminder | — | ❌ |
| Subagent Worktree | — | ❌ |
| Verification Loop | — | ❌ |
