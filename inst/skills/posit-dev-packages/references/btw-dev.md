# btw 开发版新功能（vs CRAN 1.4.0）

当前安装：`1.4.0.9000`（GitHub: `posit-dev/btw`）
当前 SHA：`d11591b09d9127b05d673e8c96569d2bbae2ec44`
最后验证：2026-08-18

## 当前开发版新增功能

### CLI 自动加载开发中的 R 包（#212）

`btw docs` 和 `btw pkg src` 现在会在当前目录（或其 `pkg-r/`、`R/` 子目录）检测正在开发的 R 包，并在运行命令前调用 `pkgload::load_all()`。因此帮助和源码查询会反映尚未安装、尚未提交的本地修改，而不是旧的已安装版本。

```bash
# 在包项目根目录中读取当前开发源码
btw pkg src get mypackage my_function

# 跳过开发目录，明确使用已安装版本
btw pkg src get mypackage my_function --no-dev
```

检测会比较项目 `DESCRIPTION` 的 `Package:` 字段与请求的包名，避免误加载无关项目。

**对 codeagent 的影响：**这是 btw CLI 的开发工作流增强。codeagent 主要调用 btw 的 R tool factories，因此没有直接运行时变化。

## CRAN 1.4.0 已包含的基线能力

以下功能已进入 CRAN 1.4.0，不再属于当前开发版相对 CRAN 的差异：

- `btw pkg src`：列出、读取、搜索 package namespace 源码及方法；
- `btw pkg desc`：显示 `DESCRIPTION` metadata；
- `btw_app()` 模型切换和 tool-result UI 改进；
- 从 `.btw/agents/`、`~/.btw/agents/` 发现自定义 agents；
- `btw_tool_files_patch()`：原子多文件 add/update/delete/rename；
- skills CLI、`btw.skills.paths` 和项目 skill 安装；
- hash 锚定的文件 read/edit/replace 工具；
- package document/check/test/coverage/load_all 工具；
- `btw_tool_agent_subagent()`。

## codeagent 文件工具集成

codeagent 仍以两类工具并存：

| 工具 | 来源 | 路径范围 | 特色 |
|---|---|---|---|
| Read/Write/Edit/MultiEdit | codeagent | 允许的绝对路径 | 中央权限门控 |
| btw file tools | btw | cwd 内 | hash 锚定、stale edit 拒绝 |
| `btw_tool_files_patch` | btw | cwd 内 | 原子多文件 patch |

`btw_tool_files_patch` 已在 `R/tools_btw_files_pathA.R` 的 Path A 中启用。btw 的 cwd 限制是安全设计，不是缺陷。

## codeagent 已落地的 Plan 37 集成

- Full-client/UI 路径不再暴露重复的 `btw_tool_agent_*`；dedicated owner 根据 shield/async/worktree 状态
  选择唯一 foreground Agent。shield active 时只保留继承同一 DataShield 的 codeagent Agent。
- Settings 中 btw groups 采用目标快照原子替换：取消的组真实移除，同时保留 core/MCP/skill/file owner；
  `set_tools()` 或 wrapper 重装失败会恢复旧 snapshot。
- wrapper 顺序冻结为 target tools → PreToolUse rewrite → central permission callback → Data Shield；
  幂等状态保存在 closure environment，不依赖会被 ellmer ToolDef 赋值剥离的 function attributes。
- btw 的复杂第三方结果经过统一 normalization，避免 ellmer complex-return deprecation warning。

上游比较：<https://github.com/posit-dev/btw/compare/94ffec5c03c870b378746e90912db4ba207fba47...d11591b09d9127b05d673e8c96569d2bbae2ec44>
