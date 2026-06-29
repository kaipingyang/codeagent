# VS Code Agent Customizations 面板详解

> 调研日期：2026-06-28  
> 参考来源：[VS Code Agent Customization 文档](https://code.visualstudio.com/docs/agent-customization/overview)

---

## 面板结构

VS Code Copilot Agent Mode 的 **Customizations** 栏包含 6 个子项：

```
Customizations
  ├── Agents       (44)
  ├── Skills       (24)
  ├── Instructions (66)
  ├── Hooks
  ├── MCP Servers  (1)
  └── Plugins
```

---

## 1. 📋 Instructions（指令）

**是什么：**  
给 AI 制定"永久规则"，不需要每次对话重复说明。相当于 Claude Code 的 `CLAUDE.md`。

**存放位置：**
- 全局：`~/.vscode/copilot-instructions.md`
- 项目级：`.github/copilot-instructions.md`
- 支持 Global / Workspace / Folder 三级作用域

**面板操作：**

| 操作 | 说明 |
|------|------|
| 查看已激活指令列表 | 显示所有加载的指令文件（全局 + 项目级） |
| 启用/禁用某条指令 | 切换某个指令文件是否生效 |
| 编辑指令内容 | 直接在 UI 中修改 Markdown 格式指令 |
| 添加新指令 | 为特定工作流创建新的规则文件 |

**内容示例：**
```markdown
# 我的编码规范
- 所有 Python 文件必须通过 ruff 格式化
- 提交前必须运行 `pytest`
- 禁止修改 `config/production.yaml`
- 注释使用中文
```

---

## 2. 🧠 Skills（技能）

**是什么：**  
按需加载的"能力包"，遵循 [Agent Skills 开放标准](https://agentskills.io)（SKILL.md 格式）。  
Agent 在判断任务匹配时自动激活，或用 `/skill:name` 手动调用。

**SKILL.md 格式：**
```yaml
---
name: pdf-tools
description: Extract text and metadata from PDF files. Use when asked to read, summarize, or parse PDFs.
license: MIT
compatibility: ["claude-code", "cursor", "gemini-cli", "vscode"]
allowed-tools: ["bash", "read"]
---

## 使用步骤
1. 运行 `pdftotext` 提取文本
2. 解析结构并返回摘要
```

**三阶段渐进加载（Progressive Disclosure）：**
```
启动时：只读 name + description（~100 tokens）
激活时：加载完整 SKILL.md body
执行时：按需加载 scripts/ references/ assets/
```

**面板操作：**

| 操作 | 说明 |
|------|------|
| 浏览已安装技能 | 列表显示 name + description |
| 启用/禁用技能 | 控制哪些技能对当前项目可见 |
| 查看技能详情 | 展开 SKILL.md 完整内容 |
| 导入技能 | 从本地目录或扩展市场安装 |
| 创建技能 | 向导式创建新 SKILL.md |
| 调用历史 | 查看该技能被触发的次数和场景 |

---

## 3. 🤖 Agents（自定义 Agent）

**是什么：**  
带有"专属角色"的子 Agent——有独立的指令、工具白名单、和模型配置。

**定义方式（`.vscode/agents/security-reviewer.md`）：**
```markdown
---
name: security-reviewer
description: Security-focused code reviewer. Checks for vulnerabilities, secrets exposure, and unsafe patterns.
model: claude-opus-4-5
allowed-tools: [read, grep]
deny-tools: [bash, write, edit]
---

你是一位专业的安全代码审查员。
只读取和分析代码，不修改任何文件。
重点检查：SQL 注入、XSS、硬编码密钥、权限绕过...
```

**面板操作：**

| 操作 | 说明 |
|------|------|
| 查看所有 Agent 定义 | 列出所有 agent 及其 description |
| 创建新 Agent | 填写 name / model / 指令 / 工具权限 |
| 编辑 Agent 配置 | 修改角色 prompt、工具白名单 |
| 测试 Agent | 在沙盒中试运行 |
| 在会话中切换 Agent | 对话中切换专属 Agent |
| 链式编排 | 配置 Agent 链（A → B → C 串行/并行）|

---

## 4. 🪝 Hooks（钩子）

**是什么：**  
在 Agent 循环的**固定节点**自动执行 shell 命令。  
提供"确定性"保障——不依赖模型记住规则，而是程序强制执行。

**支持的 8 个事件：**

| 事件 | 触发时机 |
|------|---------|
| `SessionStart` | 用户提交第一条 prompt 时 |
| `UserPromptSubmit` | 每次用户提交 prompt 时 |
| `PreToolUse` | Agent 调用工具**之前**（可阻断）|
| `PostToolUse` | 工具执行成功**之后** |
| `PreCompact` | 上下文压缩**之前** |
| `SubagentStart` | 子 Agent 被启动时 |
| `SubagentStop` | 子 Agent 完成时 |
| `Stop` | 整个会话结束时 |

**典型用例：**

```json
// .vscode/hooks.json
{
  "PostToolUse": {
    "command": "npx prettier --write ${file}"
  },
  "PreToolUse": {
    "command": "bash ./scripts/check-permissions.sh ${toolName}"
  }
}
```

| 用途 | 说明 |
|------|------|
| 自动格式化 | 每次文件编辑后运行 prettier / ruff |
| 安全拦截 | PreToolUse 中阻断危险 bash 命令 |
| 审计日志 | 所有工具调用写入日志文件 |
| Git 存档 | 每轮对话结束自动 git stash |

**面板操作：**

| 操作 | 说明 |
|------|------|
| 查看已注册钩子列表 | 按事件类型分组显示 |
| 启用/禁用某个钩子 | 临时关闭不需要的自动化 |
| 编辑钩子脚本 | 修改 shell 命令 |
| 查看执行日志 | 每个钩子的运行记录和返回值 |
| 测试钩子 | 手动触发某个事件测试效果 |

---

## 5. 🔌 MCP Servers（MCP 服务器）

**是什么：**  
Model Context Protocol 服务器——为 Agent 提供**外部工具和数据源**。  
通过标准协议让 Agent 能操作数据库、调用 API、读取文档等。

**配置方式（`.vscode/mcp.json`）：**
```json
{
  "mcpServers": {
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "/workspace"],
      "lifecycle": "lazy"
    },
    "postgres": {
      "command": "uvx",
      "args": ["mcp-server-postgres", "--connection-string", "postgres://..."],
      "lifecycle": "eager",
      "idleTimeout": 300
    },
    "github": {
      "url": "https://api.githubcopilot.com/mcp/",
      "type": "http"
    }
  }
}
```

**配置参数：**

| 参数 | 说明 |
|------|------|
| `command` / `args` | stdio 模式启动命令 |
| `url` | HTTP/SSE 模式服务器地址 |
| `lifecycle` | `lazy`（按需）/ `eager`（启动即连接）/ `keep-alive` |
| `idleTimeout` | 空闲超时（秒），超时后暂停 |
| `directTools` | 直接暴露为工具，跳过 LLM 决策 |
| `env` | 注入的环境变量（API Key 等）|

**面板操作：**

| 操作 | 说明 |
|------|------|
| 查看已连接 MCP 服务器 | 显示连接状态（在线/离线）|
| 添加新 MCP 服务器 | 填写 command 或 url + 参数 |
| 查看服务器提供的工具列表 | 展开查看该 MCP 的所有 tools |
| 启用/禁用某个工具 | 精细控制哪些 MCP 工具对 Agent 可见 |
| 查看调用日志 | 每个 MCP 工具的请求/响应记录 |
| 测试连接 | ping MCP 服务器验证配置 |

---

## 6. 📦 Plugins（插件）

**是什么：**  
将上面 5 类定制（Instructions + Skills + Agents + Hooks + MCP）**打包为一个可安装单元**。  
从市场安装一个插件，即可一次性获得完整的工作流配置。

**插件结构示例：**
```json
{
  "name": "@myorg/fullstack-dev-plugin",
  "version": "1.0.0",
  "contributes": {
    "agentPlugin": {
      "skills": ["./skills/react-component/", "./skills/api-design/"],
      "instructions": ["./instructions/typescript-style.md"],
      "hooks": { "PostToolUse": "npx prettier --write ${file}" },
      "mcpServers": { "playwright": { "command": "npx playwright-mcp" } }
    }
  }
}
```

**面板操作：**

| 操作 | 说明 |
|------|------|
| 浏览已安装插件 | 列表显示所有插件 name / version / 来源 |
| 从市场安装 | 搜索 VS Code 扩展市场中的 agent plugins |
| 启用/禁用插件 | 切换整个插件包的所有配置 |
| 查看插件内容 | 展开查看它包含的 skills / hooks / agents |
| 更新插件 | 升级到最新版本 |
| 导出配置为插件 | 将自己的配置打包发布到市场 |

> VS Code 扩展市场入口：Extensions 视图（`⇧⌘X`）→ 搜索 `@agentPlugins`

---

## 整体架构关系图

```
┌─────────────────────────────────────────────────────────────┐
│              VS Code Agent Customizations                    │
├──────────────────────────────────────────────────────────────┤
│  Instructions  │  写一次，永久生效的规则（= CLAUDE.md）      │
├──────────────────────────────────────────────────────────────┤
│  Skills        │  按需加载的能力包（SKILL.md 开放标准）      │
├──────────────────────────────────────────────────────────────┤
│  Agents        │  专属角色 + 工具权限 + 子 Agent 编排        │
├──────────────────────────────────────────────────────────────┤
│  Hooks         │  确定性自动化，8 个生命周期节点             │
├──────────────────────────────────────────────────────────────┤
│  MCP Servers   │  外部工具/数据源集成（stdio + HTTP）         │
├──────────────────────────────────────────────────────────────┤
│  Plugins       │  将以上所有配置打包为可安装/可分享单元       │
└──────────────────────────────────────────────────────────────┘
```

---

## 与 Claude Code 概念对照

| VS Code Customizations | Claude Code 对应 | 说明 |
|------------------------|-----------------|------|
| Instructions | `CLAUDE.md` | 永久项目/用户规则 |
| Skills | `.claude/skills/` | SKILL.md 标准，跨 Agent 通用 |
| Agents | Task tool / subagents | 专属角色子 Agent |
| Hooks | `settings.json` hooks | Claude Code 支持 27 种事件 |
| MCP Servers | `mcp.json` | 两者都支持 stdio + HTTP |
| Plugins | 暂无内置打包机制 | 通过 CLAUDE.md + skills 手动组合 |

---

## 参考资料

- [VS Code Agent Customization 文档](https://code.visualstudio.com/docs/agent-customization/overview)
- [VS Code Agent Plugins](https://code.visualstudio.com/docs/agent-customization/agent-plugins)
- [Agent Skills 开放标准](https://agentskills.io/specification)
