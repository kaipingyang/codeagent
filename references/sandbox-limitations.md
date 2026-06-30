# Sandbox / Execution Isolation — 现状与限制

> 日期：2026-06-30（M8）
> 状态：**未实现文件系统/网络沙箱**，本文档说明原因与缓解措施

---

## 概念图要求

Claude Code 概念图 BACKEND 层 EXECUTION ENVIRONMENT 提到：
- Bash / PowerShell 执行层
- **可选沙箱（filesystem + network isolation）**
- Remote execution

---

## codeagent 现状

| 能力 | 状态 |
|------|------|
| Bash 执行 | ✅ `bash_tool`（permission-gated）|
| RunR 执行 | ✅ `run_r_tool`（permission-gated，但 unsandboxed）|
| 文件系统隔离 | ❌ 未实现 |
| 网络隔离 | ❌ 未实现 |
| Remote execution | ❌ 未实现 |

---

## 为何不实现沙箱（务实决策）

### 1. R 无原生进程沙箱
R 解释器没有 seccomp/namespace/capability 级别的内置隔离。Claude Code（Node.js）
也依赖操作系统层（容器、bubblewrap、macOS sandbox-exec）而非语言层。

### 2. R 侧实现代价高、可靠性差
要在 R 里隔离 fs/network，可选路径都有重大缺陷：
- **`callr`/`processx` 子进程**：能隔离 R 状态，但**不隔离 fs/network**（子进程仍有完整权限）
- **容器（Docker/Podman）**：需外部依赖 + 镜像管理，且 codeagent 工具直接操作宿主文件（Read/Write/Edit），容器化会破坏核心工作流
- **bubblewrap/firejail**：Linux-only，需系统级安装，跨平台不可移植

### 3. 权限系统已提供第一道防线
codeagent 的**七模式权限门控**（`permissions.R`）是主要安全机制：
- `default`：危险操作（Bash/Write/Edit/RunR）逐个确认
- `plan`：只读，阻断所有写操作
- `dont_ask`：CI/CD 场景，非只读一律拒绝
- deny-first 规则 + Hook PreToolUse 拦截

这覆盖了沙箱的核心目标（防止未授权的破坏性操作），只是机制不同
（**人工/规则确认** vs **OS 强制隔离**）。

---

## 缓解措施（当前可用）

1. **权限模式**：生产/不可信场景用 `plan`（只读）或自定义 deny 规则
2. **PreToolUse Hook**：注册 hook 拦截危险命令（如 `rm -rf`、网络访问）
   ```r
   hooks$register_pre(function(tool, input) {
     if (tool == "Bash" && grepl("rm -rf|curl|wget", input$command))
       return(list(action = "deny", message = "blocked by policy"))
     list(action = "allow")
   })
   ```
3. **worktree 隔离**：子 agent 用 `worktree_isolation=TRUE`，在独立 git
   worktree 操作，限制对主工作区的影响（但非 fs 沙箱）
4. **外部容器**：若需真隔离，在容器内运行整个 codeagent 进程（宿主层隔离，
   非 codeagent 内部实现）

---

## 未来（若需要）

- **远程执行**：可包装 `mcptools` MCP server 在远程/容器内暴露执行工具，
  codeagent 作 MCP client 连接（M8 已有 MCP client 基础）
- **Linux 容器沙箱**：可选 `processx` + bubblewrap 包装 Bash/RunR，仅 Linux

---

## 结论

沙箱是 **OS/容器层职责**，不是 R 包内部能可靠实现的。codeagent 的安全模型
是**权限门控 + Hook 策略**（确定性人工/规则控制），与 Claude Code 的
OS 沙箱互补但不重叠。需要强隔离时，在容器内运行 codeagent。
