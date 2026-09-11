# codeagent 安全修复与代码审查修复记录

本文件记录在 `codeagent`（v0.2.3）项目上完成的安全修复、后续复审及验证结果。
第一、二轮包含早期安全审计和一般代码审查记录；第三、四轮针对权限、路径、
委派、配置和外部内容等核心安全边界进行了系统性加固。

> 修复日期：2026-09-09 ~ 2026-09-11
> 修复范围：已报告的高危安全漏洞及后续安全边界复审发现
> 验证方式：多轮独立只读复审、源码定向回归、安装包定向回归
> 当前结论：原始六项高危安全问题的定向测试均通过；2026-09-11 合并后静态复审
> 发现的 2 项高影响集成缺陷和 5 项中等可靠性/兼容性问题已完成源码修复和
> 回归测试补充，但遵照用户要求尚未运行这些新增测试。

---

## 目录

1. [当前安全结论](#当前安全结论)
2. [第三轮：权限边界与预览加固](#第三轮权限边界与预览加固)
3. [第四轮：配置来源、委派能力与网络内容边界](#第四轮配置来源委派能力与网络内容边界)
4. [第一轮：基于安全审计的修复](#第一轮基于安全审计的修复)
5. [第二轮：全面代码审查修复](#第二轮全面代码审查修复)
6. [第一、二轮已修复文件摘要](#第一二轮已修复文件摘要)
7. [历史代码审查清单](#历史代码审查清单)

---

## 当前安全结论

用户报告的六条高危攻击路径以及后续复审发现的配置、委派、patch、
路径执行一致性和外部内容问题均已修复：

| 安全边界 | 当前状态 |
|----------|----------|
| 路径授权 | 权限匹配与实际执行使用同一 canonical path；目录 containment 按组件判断 |
| Worker/Agent | 继承不可变父级策略、实际工具白名单、实现签名和 authoritative cwd |
| RunR | 默认要求真实 OS sandbox；显式 process 模式不再被描述为安全沙箱 |
| Shiny 文件预览 | 列表、选择、lazy-load、预览和附件均限制在 workspace root |
| Markdown | 使用 DOM 标签、属性和 URL scheme allowlist，移除 regex sanitizer |
| 工具集权限 | sets、capabilities、overrides、rules 由中央 gate fail-closed 执行 |
| 项目配置 | 使用严格非安全字段 allowlist，不能控制凭据、权限、sandbox、MCP 或环境 |
| 外部网页内容 | 网络工具需要相应授权；正文被标记为不可信数据并防止指令注入 |

安全定向测试已分别针对源码包和重新安装到本地的 `codeagent` 0.2.3
执行并通过。合并后的 79 个 R 源文件通过解析，91/91 个独立源码测试文件和
18/18 个已安装包安全/可靠性测试文件通过，`pkgdown::check_pkgdown()` 通过。
首次测试因已安装的 `ellmer`/`btw` 版本低于 `DESCRIPTION` 要求而未进入测试；
安装锁定 SHA 后重跑全部通过。

修复已通过提交 `ecce4704046a5d0af22b31d415ccb9c0239f269d`
推送到远程 `process` 分支；未推送到 `main`。该提交包含的最后一轮静态修复
仍遵照用户要求未运行新增测试、R CMD check、本地重装或 codegraph sync。

### 2026-09-11 合并后静态复审新增待办

用户要求停止在本地运行代码后，仅进行了源码静态复审和编辑，未启动 R、测试、
构建、安装、server 或 codegraph。以下问题已由当前实现交叉确认并完成修复，
但新增回归测试尚未运行：

| 严重性 | 问题 | 修复 |
|--------|------|------|
| HIGH | 前台 Agent 丢失父级 `ask_fn` | 注册层现在把当前 console/Shiny 审批回调传入 Agent；bubble 请求继续由父级决定 |
| HIGH | Team/Background worker 未完整继承后端 | worker context v2 携带 model/provider/base URL/API-key env selector；只有可安全重建的内部 Chat 注册进程型委派，显式 Chat 保留 clone-based 前台 Agent 并对进程委派失败关闭 |
| MEDIUM | RAG 工具缺少中央 gate metadata | 注册前后比较工具快照，并把新增 retrieval 工具登记为 set A/net；自动索引要求 net 允许、set A 启用且 Data Shield 未激活 |
| MEDIUM | project-scope setup 写入后被安全 allowlist 丢弃 | provider setup 现在明确只允许 user scope；项目特定后端使用显式 Chat |
| MEDIUM | 旧格式 memory 更新产生重复文件 | 缺少 `title` 时按旧 `name` slug 与新标题计算出的 slug 比较 |
| MEDIUM | Windows 替换存在目标文件缺失窗口 | fallback 不再移走目标文件；保留固定 recovery copy、覆盖后校验哈希，并在下次写入前恢复中断状态 |
| MEDIUM | 无 `callr` 时 DNS 无硬超时 | 保留 fallback，改由必需依赖 `processx` 启动隔离解析进程并实施 10 秒硬超时 |

新增测试覆盖审批回调传递、worker 后端快照与重建、RAG metadata、project setup
拒绝、旧 memory 升级、Windows recovery copy 和 processx DNS fallback。当前只能
确认静态接线完整；在用户允许恢复本地执行前，不能把新增测试标记为已通过。

关联路径也同步收口：worker 快照改为在全部非委派工具注册后获取；模型切换和
btw 动态工具组更新会重建委派闭包并保留审批回调；Data Shield 安装失败会中止
或回滚；计划模式始终允许 `ExitPlanMode`；session/memory 读取前执行 recovery
sweep；全局 session lookup 可以在合法 projects root 内 fork；camelCase
`effortLevel` 会规范化并传递给 worker。

---

## 第三轮：权限边界与预览加固

本轮针对 2026-09-10 复核确认的六条高危攻击路径，统一安全边界而非继续增加黑名单：

| 项目 | 修复 |
|------|------|
| 文件权限 canonical path | 新增共享 canonical path 与组件级 containment；不存在的写入目标通过最近已存在祖先解析；权限匹配和实际文件操作使用同一规范路径 |
| Worker 权限继承 | TeamRun、TeamCoordinate、BackgroundAgent 和前台 Agent 使用不可变父级安全快照，完整携带 mode、rules、sets、capabilities、overrides、sandbox；恢复失败即拒绝 |
| Worker 启动隔离 | mirai daemon 从中性临时目录启动，清空 R profile/environ 启动指针并固定已验证库路径；settings `env` 禁止覆盖 R 启动控制变量 |
| RunR 隔离契约 | `sandbox$enabled=TRUE` 默认要求真实 OS backend 并失败关闭；`run_r_backend="process"` 是显式 best-effort callr 回退，不再宣称文件系统或网络隔离 |
| Shiny 文件边界 | lazy-load、选择、预览和附件入口统一校验 canonical workspace root；移除无边界 `startsWith()` 判断 |
| Markdown XSS | 删除 regex sanitizer，改为 xml2 DOM 解析、标签/属性 allowlist 和 URL scheme allowlist |
| Tool sets | 中央 gate 在 override/mode 之前强制 metadata 和 enabled sets；未知工具默认拒绝，gate 安装失败中止 client 创建 |

Data Shield 无法安全序列化其运行时受保护数据索引，因此 Team 和
BackgroundAgent 在 Data Shield 激活时保持禁用，使用可继承同一实例的前台 Agent
作为明确兜底。

### 第三轮验证状态

- 79 个 `R/` 源文件全部通过语法解析。
- 权限 gate、路径规则、文件工具、文件预览、RunR、Team/Background/Agent、
  Data Shield 子 Agent、client factory 和 backend contract 定向回归全部通过。
- Windows 当前环境不允许测试创建符号链接，因此 dangling-symlink 用例按测试设计跳过；
  其他 canonical-path 用例通过。
- 当前源码已通过 `pak::local_install(".", ask = FALSE, upgrade = FALSE)` 安装为
  本地 `codeagent` 0.2.3，并确认 `xml2` 运行时依赖可用。
- `pkgdown::check_pkgdown()` 因当前环境没有 Pandoc 无法执行；未把环境缺失误报为检查通过。
- `codegraph sync` 因当前环境没有 `codegraph` 可执行文件无法执行；代码与已安装包不受影响，
  符号索引需在安装该工具的环境中补同步。
- 未执行 commit、push 或 GitHub 上传。

---

## 第四轮：配置来源、委派能力与网络内容边界

本轮针对第三轮之后的全仓复核结果修复 3 项 HIGH 和 1 项 MEDIUM：

| 项目 | 修复 |
|------|------|
| 项目配置信任边界 | 用户配置与项目配置分开读取；项目 `.codeagent/settings.json` 不得修改 provider/base URL、credential selector、进程 `env`、权限、工具策略、sandbox、hooks、MCP 或工具启用开关 |
| Worker 能力不扩张 | 安全快照增加 `file_tools`、`btw_groups`、ExploreData/RAG 开关和父级实际工具名；Team、Background 和前台 Agent 重建后删除父级未注册工具并验证最终集合 |
| 路径型工具统一门控 | `.TOOL_META` 声明路径参数；LS、Lint、Format、NotebookRead/Edit 和 btw read/list/write/edit/replace 全部 canonicalize；btw patch 检查每个 source/destination |
| 外部内容/XPIA | WebFetch/WebSearch 从本地只读自动放行集合移除；default 需要批准，plan/dont_ask 默认拒绝；网页正文使用随机服务端边界包装，系统提示始终声明其为不可信数据 |

细粒度 deny 规则在工具名称匹配但路径无法安全提取时失败关闭。前台 Agent
不再使用固定核心工具集合，而是与独立 worker 共享同一配置快照和父级工具白名单。

后续独立复审追加并关闭了以下旁路：

- 项目设置改为正向允许列表；重复、空或无效顶层 JSON 键会使整份项目配置被忽略，
  防止重复键残留危险值。
- btw patch 使用 btw 自身的解析器检查每个 `path` 和 `move_to`；多目标 allow 必须覆盖
  全部目标，任一 deny 始终优先。
- 路径型工具在执行包装层接收与 gate 相同的 canonical 参数；无显式路径的
  `btw_tool_files_search` 也固定在 client cwd 执行。
- Worker 快照除工具名外保存基础实现签名；同名异构工具不会因名称相同而被继承。
- 安全快照 cwd 不可被普通调用参数覆盖；仅 TeamCoordinate 内部成功创建的 worktree
  可使用显式 trusted override。

最终只读复审未发现达到 CRITICAL/HIGH/MEDIUM 阈值的剩余问题。

### 第四轮验证状态

- 全部 R 源文件通过语法解析。
- settings、permissions、central gate、文件工具、worker/Agent、动态 btw group、
  web citation、client factory 和 backend contract 定向回归通过。
- 三次独立只读安全复审逐步发现并关闭重复 JSON 键、patch 多目标规则、
  cwd 绑定、动态旧快照、同名异构工具和 cwd 覆盖旁路；末次复审未发现
  CRITICAL/HIGH/MEDIUM 剩余问题。
- 全量测试仍存在本任务前已知的 addin helper、可选 shinyglass、code-audit 和
  custom agent fixture 失败；安全定向套件无失败。
- 当前源码已重新安装为本地 `codeagent` 0.2.3，并使用已安装包再次运行安全
  定向套件，结果通过。
- 未执行 commit、push 或 GitHub 上传。

---

## 第一轮：基于安全审计的修复

来源：`codeagent-main` 的 `CODE-REVIEW-REPORT.md`（8 项安全漏洞）

### V-01：ExploreData 绕过执行权限

| 项目 | 内容 |
|------|------|
| **漏洞** | `ExploreData` 被标记为 `read` 能力，但其内部执行 `eval(parse(text = code))`，可运行任意 R 代码 |
| **文件** | `R/tools_gate.R` |
| **修复** | 将 `.TOOL_META` 中 `ExploreData` 改为 `"exec"`、`Lint` 改为 `"exec"`（lintr 可执行代码）、`NotebookEdit` 改为 `"write"` |
| **补充** | 未分类工具的默认能力从 `"read"` 改为 `"exec"`（`tools_gate.R:.tool_capability`），未经注册的工具不再被自动放行 |

### V-02：Grep 参数 shell 命令注入

| 项目 | 内容 |
|------|------|
| **漏洞** | `R/tools_search.R` 使用 `system2(rg_path, args)` 执行 ripgrep，`pattern` 和 `glob` 参数未经 shell 安全引用，可注入额外命令 |
| **文件** | `R/tools_search.R`, `DESCRIPTION` |
| **修复** | 替换 `system2()` 为 `processx::run()`（保持参数边界）；添加 `--` 参数分隔符防止模式被解析为选项；添加 `--no-config` 防止项目级 `.ripgreprc` 改变执行行为；在 `DESCRIPTION` 的 `Imports` 中添加 `processx` |

### V-03：Bash 只读命令前缀匹配绕过

| 项目 | 内容 |
|------|------|
| **漏洞** | `check_permission()` 使用 `.is_bash_readonly()`（`^ls\\b`、`^cat\\b` 等前缀正则）自动放行 Bash 命令；`ls; rm -rf /`、`find . -exec`、`env bash -c` 均可绕过 |
| **文件** | `R/permissions.R` |
| **修复** | 从 `check_permission()` 中移除整个 Bash 前缀自动批准逻辑；Bash 在 `default` 模式下始终需要确认 |

### V-04：团队 worker 权限继承

| 项目 | 内容 |
|------|------|
| **漏洞** | `team_run()` 和 `team_coordinate()` 默认 `permission_mode = "bypass"`，worker 不继承父级策略 |
| **文件** | `R/team.R`, `R/team_board.R`, `R/async_agent.R` |
| **修复** | 默认权限从 `"bypass"` 改为 `"dont_ask"`；`team_run()` 新增 `parent_rules` 和 `parent_policy` 参数，序列化传递给 worker；`team_coordinate_tool()` 同理更新文档和默认值；`.bg_spawn()` 默认改为 `"dont_ask"` |

### V-05：只读快捷路径跳过拒绝规则

| 项目 | 内容 |
|------|------|
| **漏洞** | `R/tools_gate.R` gate 函数中 `continue_after_shield` 对 `cap == "read"` 的工具提前返回 `invisible()`，跳过 `settings$tools$overrides` 和 `check_permission` 中的显式 `deny` 规则 |
| **文件** | `R/tools_gate.R` |
| **修复** | 移除 `if (!shield_ask && is.null(ov) && identical(cap, "read")) return(invisible())` 提前返回路径；所有工具都经过完整 `gate_decide()` 决策 |

### V-06：Markdown 预览 XSS

| 项目 | 内容 |
|------|------|
| **漏洞** | `R/server_right.R` 将 `commonmark::markdown_html()` 输出直接插入 Shiny 主页面，Malicious Markdown 文件可执行任意 JavaScript |
| **文件** | `R/server_right.R` |
| **修复** | 添加 `.sanitize_markdown_html()` 函数，在渲染前清除 `<script>`、`<iframe>`、事件处理器、 `javascript:` 链接、`data:` URI |

### V-08：MCP 自动连接

| 项目 | 内容 |
|------|------|
| **漏洞** | `.mcp_autoconnect()` 从 settings.json 和项目 `.mcp.json` 自动读取 MCP 配置并启动子进程，但默认 `enable_all_project_mcp_servers = FALSE` 未生效 |
| **文件** | `R/mcp_client.R` |
| **修复** | 将 `.mcp_autoconnect()` 改为空操作（no-op），仅返回 `invisible(0L)`；仅显式 `codeagent_client(mcp_config = ...)` 可连接 MCP 服务器 |

---

### 第一轮补充加固项

| 修复项 | 文件 | 说明 |
|--------|------|------|
| Wear 默认权限 | `R/wear.R` | `wear_explore()` 默认 `permission_mode` 从 `"bypass"` 改为 `"default"` |
| Agent 工具注册模式 | `R/tools_agent.R` | `register_builtin_tools(sub_chat, mode = ...)` 从 `"bypass"` 改为 `"dont_ask"` |
| ExploreData 描述修正 | `R/tools_data.R` | 移除"read-only"声明，改为"此工具执行 R 代码并可能有副作用" |
| Team 工具传递父级权限 | `R/query.R` | `.register_all_tools()` 调用 `register_team_tool()` 时传入 `parent_rules` 和 `parent_policy` |
| `register_tool_meta` 文档更新 | `R/tools_gate.R` | 默认能力说明从 `"read"` 改为 `"exec"` |
| Executor 并发安全 | `R/executor.R` | 移除 Bash 只读命令的并发安全判断，Bash 始终视为不安全 |

---

## 第二轮：全面代码审查修复

来源：对 `codeagent`（v0.2.3）全部约 80 个 R 源文件的静态审查，发现 54 个问题（10 HIGH / 25 MEDIUM / 19 LOW）。

以下为已修复的部分。

### HIGH

#### H-01：文件树预览路径穿越

| 项目 | 内容 |
|------|------|
| **位置** | `R/server_right.R:82-85` |
| **问题** | `selected_paths()` 来自 jsTreeR JavaScript 控件，可发送任意路径（如 `../../../etc/passwd`）。`normalizePath` 并不拒绝指向 `cwd` 外的路径 |
| **修复** | 添加路径穿越防护：拒绝 `startsWith(path, cwd_norm)` 为 FALSE 的路径 |

#### H-02：Markdown HTML 净化器不完整

| 项目 | 内容 |
|------|------|
| **位置** | `R/server_right.R:296-308` |
| **问题** | 原正则未覆盖 `<svg onload>`、`<details ontoggle>`、`data:` URI、反引号事件处理器、javascript 空格混淆等 |
| **修复** | 增强 `.sanitize_markdown_html()`，添加 `<svg>`/`<details>`/`<body>`/`<form>`/`<math>` 标签净化、反引号事件处理器剥离、data: URI 和 javascript: 空格混淆阻断 |

#### H-03：会话 ID onclick XSS

| 项目 | 内容 |
|------|------|
| **位置** | `R/server_sessions.R:39` |
| **问题** | `sprintf("Shiny.setInputValue('ca_load_session','%s',...)", sid)` 中 `sid` 来自文件名，恶意 `.jsonl` 文件名含 `'` 可逃逸字符串上下文 |
| **修复** | 使用 `htmltools::htmlEscape(sid, attribute = TRUE)` 转义 |

#### H-04：会话 ID 路径穿越

| 项目 | 内容 |
|------|------|
| **位置** | `R/server_sessions.R:73-76` |
| **问题** | `sid <- input$ca_load_session` 来自客户端，未校验直接传入 `restore_session_into_chat(chat, session_id = sid, ...)` |
| **修复** | 使用 `.validate_uuid(sid)` 验证 session ID 格式，拒绝非 UUID 值 |

#### H-05：fork_session 目的目录穿越

| 项目 | 内容 |
|------|------|
| **位置** | `R/mutations.R:130-131` |
| **问题** | `dest_dir <- dirname(src_path)` 若源路径通过遍历获得，fork 可向任意目录写入文件 |
| **修复** | 添加路径遍历防护：校验 `dest_dir_norm` 必须以 `session_dir_norm` 开头 |

#### H-06：Promise 拒绝未处理

| 项目 | 内容 |
|------|------|
| **位置** | `R/tool_normalization.R:18-19` |
| **问题** | `promises::then(value, .normalize_tool_output)` 未提供 `onRejected` 回调，Promise 拒绝时产生未处理异常 |
| **修复** | 添加 `onRejected` 回调，将拒绝转换为错误字符串 |

#### H-07：背景命令临时文件泄漏

| 项目 | 内容 |
|------|------|
| **位置** | `R/tools_bash.R:44-57` |
| **问题** | `run_in_background = TRUE` 分支创建 `.sh` 临时文件后从未清理 |
| **修复** | `writeLines(command, tmp)` 之前添加 `on.exit(unlink(tmp), add = TRUE)` |

#### H-08：Write 工具缺少路径标准化

| 项目 | 内容 |
|------|------|
| **位置** | `R/tools_fs.R:88-133`, `R/utils.R:177-182` |
| **问题** | Write 直接使用 `file_path`，未调用 `.safe_normalize_path()`；`dir.create(recursive = TRUE)` 在权限批准前已执行副作用 |
| **修复** | Write 工具在权限检查后调用 `.safe_normalize_path(file_path, allow_missing = TRUE)`；`utils.R` 中 `.safe_normalize_path` 新增 `allow_missing` 参数 |

#### H-09：Edit/MultiEdit destructive_hint 错误

| 项目 | 内容 |
|------|------|
| **位置** | `R/tools_fs.R:211,301` |
| **问题** | Edit 和 MultiEdit 均修改文件系统但声明 `destructive_hint = FALSE`，UI 层不会对破坏性操作发出警告 |
| **修复** | 改为 `destructive_hint = TRUE` |

#### H-10：RunR 沙箱基于正则屏蔽可绕过

| 项目 | 内容 |
|------|------|
| **位置** | `R/tool_run_r.R:42-51`, `R/sandbox.R:158-203` |
| **问题** | `.SANDBOX_R_SHELL_FNS` 和 `.SANDBOX_R_NETWORK_FNS` 使用静态正则匹配函数名。`get("system")("cmd")`、`do.call("system", ...)`、注释分割等方式均可绕过 |
| **修复** | 在沙箱启用但 `callr` 不可用时，拒绝执行并提示安装 `callr` 包，不再依赖可绕过的黑名单 |

### MEDIUM

#### M-01：保存会话没有原子写入

| 项目 | 内容 |
|------|------|
| **位置** | `R/sessions.R:118` |
| **问题** | `save_session` 使用 `writeLines(lines, file_path)` 直接写入，进程崩溃时产生截断/损坏的文件 |
| **修复** | 改为临时文件 + `file.rename` 原子写入模式，防止崩溃导致文件损坏 |

#### M-04：技能安装包名未验证

| 项目 | 内容 |
|------|------|
| **位置** | `R/server_customizations.R:64-84` |
| **问题** | `trimws(input$install_skill_pkg)` 直接传给 `btw::btw_skill_install_package`，包名中的 shell 元字符可能造成命令注入 |
| **修复** | 添加包名正则校验（`^[a-zA-Z][a-zA-Z0-9._-]+$`）和 scope 白名单校验（`c("project", "user")`） |

#### M-05：settings$permission_mode 来自客户端未校验

| 项目 | 内容 |
|------|------|
| **位置** | `R/server_settings.R:66,80` |
| **问题** | `settings$permission_mode <<- input$perm_mode` 和 `settings$btw_groups <<- input$btw_groups_input` 来自 Shiny 客户端但未校验 |
| **修复** | `perm_mode` 添加 `PermissionMode` 白名单校验；`btw_groups` 添加 `is.character` 类型校验 |

### LOW

#### L-04：嵌套 EnterPlanMode 的 prev 覆盖

| 项目 | 内容 |
|------|------|
| **位置** | `R/tools_plan.R:21-33` |
| **问题** | 连续两次调用 `EnterPlanMode` 时，第二次用 `"plan"` 覆盖 `mode_env$prev`，退出时恢复为 `"default"` 而非原始模式 |
| **修复** | 仅当当前模式不是 `"plan"` 时才更新 `prev` |

#### sessions.R 残留 writeLines 清理

| 项目 | 内容 |
|------|------|
| **位置** | `R/sessions.R:118` |
| **问题** | 之前的修复添加了临时文件 + rename 原子写入，但旧的 `writeLines(lines, file_path)` 未删除 |
| **修复** | 删除旧的 `writeLines` 调用 |

---

## 第一、二轮已修复文件摘要

下表是第一、二轮记录形成时的历史摘要，不包含第三、四轮后来扩展到
settings、worker 快照、执行包装、网络内容和完整路径型工具覆盖的修改。

| 文件 | 修复数量 | 涉及问题 |
|------|----------|----------|
| `R/tools_gate.R` | 4 | V-01, V-05, 工具分类, 默认能力 |
| `R/permissions.R` | 1 | V-03 |
| `R/tools_search.R` | 1 | V-02 |
| `R/executor.R` | 1 | Bash 并发安全移除 |
| `R/team.R` | 1 | V-04 (team_run 权限继承) |
| `R/team_board.R` | 1 | V-04 (team_coordinate 默认权限) |
| `R/async_agent.R` | 1 | V-04 (background agent 默认权限) |
| `R/mcp_client.R` | 1 | V-08 (MCP 自动连接 no-op) |
| `R/tools_agent.R` | 1 | Agent 注册模式改为 dont_ask |
| `R/wear.R` | 1 | Wear 默认权限改为 default |
| `R/tools_data.R` | 1 | ExploreData 描述修正 |
| `R/query.R` | 1 | Team 工具传递父级权限 |
| `R/server_right.R` | 3 | V-06, H-01, H-02 |
| `R/server_sessions.R` | 2 | H-03, H-04 |
| `R/mutations.R` | 1 | H-05 |
| `R/tool_normalization.R` | 1 | H-06 |
| `R/tools_bash.R` | 1 | H-07 |
| `R/tools_fs.R` | 2 | H-08, H-09 |
| `R/tool_run_r.R` | 1 | H-10 |
| `R/sessions.R` | 1 | M-01 |
| `R/server_customizations.R` | 1 | M-04 |
| `R/server_settings.R` | 1 | M-05 |
| `R/tools_plan.R` | 1 | L-04 |
| `R/utils.R` | 1 | H-08 (allow_missing 参数) |
| `DESCRIPTION` | 1 | V-02 (processx 依赖) |

第三、四轮的主要修改文件包括 `R/settings.R`、`R/permissions.R`、
`R/tools_gate.R`、`R/tool_input_hook.R`、`R/utils.R`、`R/team.R`、
`R/team_board.R`、`R/async_agent.R`、`R/tools_agent.R`、`R/tools_r.R`、
`R/tools_web.R`、`R/prompts.R`、`R/server_right.R`、`R/tool_run_r.R`、
`R/sandbox.R` 和 `R/mcp_client.R`，并同步更新相关测试与 `README.md`。

---

## 历史代码审查清单

以下清单来自第二轮范围更广的一般代码审查，保留用于历史追踪。它混合了
安全、可靠性、性能、文档一致性和架构改进项，**不能直接解释为当前仍存在
21 个 MEDIUM 安全漏洞**。2026-09-11 已根据 `process@ecce470` 完成静态同步：
8 项已修复、5 项原判断已失效、1 项部分解决、7 项仍待处理。未运行 R、测试、
构建或安装，因此“已修复”表示当前源码和已有测试接线支持该结论，不代表本轮
新增修改已经通过运行时验证。

### HIGH（原报告已修复）

| ID | 文件 | 行号 | 问题描述 | 状态 |
|----|------|------|----------|------|
| V-01 | `R/tools_gate.R`, `R/tools_data.R` | 65-70, 260 | ExploreData 以只读身份执行任意 R 代码 | ✅ 已修复 |
| V-02 | `R/tools_search.R` | 93-103 | Grep 参数 shell 命令注入 | ✅ 已修复 |
| V-03 | `R/permissions.R` | 94-98, 156-170 | Bash 只读前缀匹配可被复合命令绕过 | ✅ 已修复 |
| V-04 | `R/team.R`, `R/team_board.R`, `R/async_agent.R`, `R/tools_agent.R` | worker 创建路径 | Worker 未完整继承父级策略 | ✅ 已修复（第三轮完整安全快照） |
| V-05 | `R/tools_gate.R` | 259-263 | 只读快捷路径跳过拒绝规则 | ✅ 已修复 |
| V-06 | `R/server_right.R` | Markdown 预览 | Markdown 预览 XSS | ✅ 已修复（第三轮 DOM allowlist） |
| V-08 | `R/mcp_client.R`, `R/query.R` | 118-146, 286-290 | MCP 自动连接绕过关闭标志 | ✅ 已修复 |
| H-01 | `R/server_right.R` | 文件树入口 | 文件树预览路径穿越 | ✅ 已修复（所有入口 canonical containment） |
| H-02 | `R/server_right.R` | Markdown sanitizer | Markdown HTML 净化器不完整 | ✅ 已修复（DOM allowlist） |
| H-03 | `R/server_sessions.R` | 39 | 会话 ID onclick XSS | ✅ 已修复 |
| H-04 | `R/server_sessions.R` | 73-76 | 会话 ID 路径穿越 | ✅ 已修复 |
| H-05 | `R/mutations.R` | 130-131 | fork_session 目的目录穿越 | ✅ 已修复 |
| H-06 | `R/tool_normalization.R` | 18-19 | Promise 拒绝未处理 | ✅ 已修复 |
| H-07 | `R/tools_bash.R` | 44-57 | 背景命令临时文件泄漏 | ✅ 已修复 |
| H-08 | `R/tools_fs.R` | 88-133 | Write 路径未标准化 | ✅ 已修复 |
| H-09 | `R/tools_fs.R` | 211, 301 | Edit/MultiEdit destructive_hint 错误 | ✅ 已修复 |
| H-10 | `R/tool_run_r.R` | 42-51 | RunR 沙箱正则屏蔽可绕过 | ✅ 已修复 |

### MEDIUM（2026-09-11 静态同步）

| ID | 当前位置 | 状态 | 同步结论 |
|----|----------|------|----------|
| M-02 | `R/memory.R:42-102` | 部分解决 | memory 文件和索引已使用临时文件及校验替换，但整个 read-modify-write 事务仍无文件锁，并发 writer 仍可能覆盖索引更新 |
| M-03 | `R/server_slash.R:149-152` | 已修复 | 本地斜杠命令名称以反引号代码形式回显，不再作为原始 HTML/Markdown 插入 |
| M-06 | `R/executor.R:41-42,172-190` | 已修复 | 同步 `submit()` 已明确为串行路径；并行能力仅由 async batch 的 `promise_all()` 提供，行为与文档一致 |
| M-07 | `R/sandbox.R:44-94` | 已失效 | `unshare` 缓存是进程级能力探测和一次性告警，不携带单个 Chat 的策略状态，未形成多实例权限串扰 |
| M-08 | `R/compaction.R:263-300,406-548` | 待处理 | `snip_old_tools()` 会先写入 Chat history，后续压缩阶段失败或提前返回时仍缺少统一 snapshot/rollback |
| M-09 | `R/compaction.R:550,1529-1534` | 已修复 | `post_compact_still_large` 和 `full_disabled` 已从断路器失败计数中排除，并有定向测试覆盖 |
| M-10 | `R/context.R:109-117` | 已修复 | 1M 模型标记已改为结尾锚定匹配 `\\[1m\\]$` |
| M-11 | `R/tools_bash.R:44-56` | 待处理 | 后台 `system2(wait = FALSE)` 仍不实施 timeout，也没有 PID 跟踪和终止机制 |
| M-12 | `R/tools_web.R:51-54` | 待处理 | `prompt` 参数仍保留为兼容参数但未参与提取；需明确实现、弃用或从公开契约移除 |
| M-13 | `R/hooks.R:103,164-169` | 已修复 | Hook registry 已跳过废弃或不可触发的事件，不再为其创建空 bucket |
| M-14 | `R/data_shield.R:1256-1264,1337-1342` | 待处理 | 工具参数逐项扫描时仍会重复构建 regex scanner，属于性能优化项 |
| M-15 | `R/constants.R:47`, `R/settings.R:211-218` | 待处理 | 未识别模型仍回退到 200K context；已有 warning，但预算仍可能高估，应采用保守默认值或显式配置 |
| M-16 | `R/settings.R:320-336` | 已失效 | `max_depth` 当前定义为 next-hop guard，测试确认第 6 次导入会被阻止，现有行为符合约定 |
| M-17 | `R/budget.R:73-76` | 已失效 | 美元硬上限触发后立即终止；停止后的 `prev_tokens` 不再被消费，无需更新 |
| M-18 | `R/prompts.R:251` | 待处理 | 首轮 reminder 仍可能调用模型进行相关记忆召回，尚无结果缓存或内容未变跳过机制 |
| M-19 | `R/ui.R:750-763`, `R/server_chat.R:139-140` | 已失效 | 相关 R6 controller 通过 `isolate()` 命令式读取，当前没有依赖其内部突变自动触发的 reactive consumer |
| M-20 | `R/ui_panels.R:36-40` | 待处理 | `voice.js` 已随包提供，但读取入口仍未检查空路径或读取失败；安装损坏或资源缺失时仍可能阻止 UI 启动 |
| M-21 | `R/server_sessions.R:58-77` | 已修复 | load/delete 使用客户端 session ID 前均执行 UUID 校验 |
| M-22 | `R/server_interaction.R:68` | 已修复 | Egress 审批使用 `event$timeout %||% 60`，支持逐事件配置 |
| M-23 | `R/sandbox.R:126-132` | 已修复 | 网络阻断规则扫描完整命令文本，覆盖管道和复合命令中的网络工具 |
| M-24 | `R/sandbox.R:148-154` | 已失效 | `system2(env=)` 的公开契约就是 `NAME=VALUE` 字符串；名称后的第一个 `=` 是分隔符，值中继续包含 `=` 不构成所述截断问题 |

仍待处理的 M-08 涉及压缩失败后的状态一致性；M-11 和 M-20 涉及进程及启动
可靠性；M-12 属于 API 行为收口；M-14、M-18 属于性能；M-15 属于未知模型的
预算保守性。M-02 的原子替换已经降低损坏风险，但并发一致性仍需文件锁或等价
事务机制。这些条目不应整体表述为已确认的安全漏洞。

### LOW（历史待办，需按当前代码重新验证）

| # | 文件 | 行号 | 问题描述 | 修复建议 |
|---|------|------|----------|----------|
| L-01 | `R/tools_fs.R` | 35 | `.gitignore` 等点文件的 `tools::file_ext()` 返回 `"gitignore"`，标记为无效 markdown 语言标签 | 对点文件使用空扩展名 |
| L-02 | `R/tools_r.R` | 207-237 | `verify_r_tests` 和 `.devtools_available` 可能为死代码（无工具调用） | 审计后删除或添加实际调用 |
| L-03 | `R/tools_todo.R` | 50-57 | `.coerce_todos` 的 `data.frame` 分支从不会被 ellmer 触发，逻辑有误 | 删除 `data.frame` 分支或修正逻辑 |
| L-05 | `R/permissions.R` | 37-40 | `.READONLY_TOOLS` 包含 `WebFetch`/`WebSearch`，但这些工具有网络副作用 | 移除或加注释说明网络不是"写入" |
| L-06 | `R/context.R` | 194 | `.auto_compact_threshold` 在一次 `calculate_token_warning_state` 中被调用两次 | 缓存第一次调用的结果 |
| L-07 | `R/compaction.R` | 382 | `proc.time()[["elapsed"]]` 用作默认参数但在函数体内重新计算参考时间 | 统一使用 start/end 模式 |
| L-11 | `R/settings.R` | 173-175 | `CODEAGENT_MAX_BUDGET_USD=0` 被静默忽略（无警告） | 添加值为 0 时的警告 |
| L-12 | `R/sessions.R` | 321-323 | `restore_session_into_chat` 在工具注册表已更改时使用旧会话的工具回调 | 检查工具签名是否匹配 |
| L-13 | `R/hooks.R` | 461-463 | `.hook_pattern_matches` 的 glob 转换只处理 `*`，不支持 `?` 和 `[abc]` | 改用完整 glob 转换 |
| L-14 | `R/memory.R` | 83-90 | `list_memories` 的 front-matter 解析在缺少 `---` 关闭符时使 body 为空（无警告） | 添加缺少关闭符的警告 |
| L-15 | `R/memory.R` | 57 | `write_memory` 中 slug 冲突静默覆盖旧记忆 | 检测冲突并添加后缀或报错 |
| L-16 | `R/tools_web.R` | 265-270 | HTML 实体解码器仅处理 6 个实体（如 `&amp;`），其余保留原始文本 | 使用 `xml2::xml_text` 进行完整解引用 |
| L-17 | `R/tools_web.R` | 261-274 | 空白规范化破坏缩进格式化内容 | 仅在纯文本段落应用空白规范化 |
| L-18 | `R/tools_fs.R` | 165-169 | Edit 在错误时返回原始字符串而非 `.artifact_tool_result`，与工具其余部分不一致 | 统一使用 `.artifact_tool_result` |
| L-19 | `R/tool_display.R` | 704 | `_rand_id()` 使用 8 字符随机字符串，可能产生 DOM ID 冲突 | 增加字符数或使用 UUID |

### 历史复审备注

以下问题经复审认为影响有限，不作为当前处理重点：

| 问题 | 说明 |
|------|------|
| M-17 预算停止不更新 prev_tokens | `should_stop` 返回 TRUE 后不再调用，prev_tokens 无意义 |
| M-20 voice.js 缺失导致崩溃 | `voice.js` 是包自带资产，安装后必然存在 |
| L-05 WebFetch/WebSearch 在 readonly 列表中 | 网络读取不属于"写入"操作，分类合理 |
| H-08 剩余 sandbox 项 | `sandbox.R` 中 `.sandbox_env` 的 `paste0(names, "=", vals)` 是标准格式，不存在解析歧义问题 |

### 结构性/架构级别问题

| 问题 | 说明 |
|------|------|
| V-07（多用户历史隔离） | 需要认证主体 + 持久化存储隔离，属于架构级别需求 |
| 多文件竞态条件 | `sessions.R`、`memory.R`、`settings.R` 等文件的"读取→修改→写入"模式在单用户场景下安全；多实例需要文件锁机制 |
| 异步/并发路径一致性 | `executor.R` 同步路径是串行的；无缝并行需要 `callr`/`mirai` 级别的多进程调度 |