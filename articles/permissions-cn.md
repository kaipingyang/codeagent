# 权限系统

**语言：**
[English](https://kaipingyang.github.io/codeagent/articles/permissions.md)
\| 简体中文

每个已注册的工具调用在执行前都会经过同一个中央授权门。原生工具、btw
工具、 Format 工具和 MCP 工具均以 bypass 模式构建；安装在
`chat$on_tool_request`
上的权限门是唯一的权限判定机构。如果该回调无法注册，
权限门安装会以失败关闭（fail-closed）的方式终止。

## 权限门如何判定

    模型请求工具
        |
        v
    chat$on_tool_request -> 中央权限门（.tool_gate_fn）
        |
        +- Data Shield 入口扫描（启用 Shield 时；覆盖每个工具）
        |     阻止/错误 -> PermissionDenied -> ellmer::tool_reject()
        |
        +- capability == read、没有逐工具 override、且 Shield 未要求询问？
        |     是 -> 权限门直接 ALLOW（快速路径）
        |
        v  .gate_decide()（优先级从高到低）
      1. settings$tools$overrides[tool]      -> allow / deny / ask
      2. settings$tools$capabilities[class]  -> write|exec|net -> allow/deny/ask
      3. 回退到 check_permission(mode, rules)：
           plan          -> 在检查规则前拒绝非读取操作
           用户规则      -> 第一个匹配的 glob 生效
           accept_edits  -> 允许编辑工具
           bypass        -> 允许
           bubble        -> ask（由父代理/宿主处理）
           dont_ask      -> 允许只读，否则拒绝
           auto          -> 快速模型分类为 allow/deny/ask
           default       -> 允许只读和识别出的只读 Bash；否则 ask
        |
        v
      决策 -------+-- deny -> PermissionDenied -> ellmer::tool_reject()
                  +-- ask  -> ask_fn()：CLI 控制台提示或 Shiny 异步审批条
                  |            拒绝/错误/无 ask_fn -> deny
                  |            批准 -> 继续
                  +-- allow -------------------------> 继续
                                                        |
                                                        v
                             PreToolUse 包装层：拒绝或重写参数；
                             重写后的参数会再次经过权限门/Shield 检查
                                                        |
                                                        v
                             执行工具 -> on_tool_result -> PostToolUse hook

读取快速路径是有意设计：只要工具能力为 `read`、没有显式逐工具
override，且 Shield 未要求询问，它会在 Shield
扫描后、能力策略/规则/模式回退之前被权限门
允许。若某个读取工具必须询问或拒绝，请使用
`settings$tools$overrides`。为了兼容， 未知的宿主工具会默认为 `read`
能力，因此宿主应通过
[`register_tool_meta()`](https://kaipingyang.github.io/codeagent/reference/register_tool_meta.md)
或安装 权限门时的 `tool_meta` 声明其真实能力。

`settings$tools$sets`（`"A"` = codeagent 核心，`"B"` =
btw）控制注册哪些工具集； 这是注册策略，不是逐调用决策。

## 模式

下表描述回退行为。逐工具 override 或非读取能力策略可以覆盖这些行为。

| 模式           | 回退行为                                           |
|----------------|----------------------------------------------------|
| `default`      | 允许只读工具和识别出的只读 Bash 命令；其他调用询问 |
| `plan`         | 在用户规则前拒绝非读取调用；允许读取工具           |
| `accept_edits` | 允许文件编辑工具；其他非读取调用仍会询问           |
| `bypass`       | 允许所有调用（请谨慎使用）                         |
| `dont_ask`     | 允许只读调用并拒绝非读取调用，适合无人值守运行     |
| `auto`         | 由配置的快速模型把调用分类为 allow、deny 或 ask    |
| `bubble`       | 返回 ask，让父代理或宿主审批回调决定               |

``` r

client <- codeagent_client(chat, permission_mode = "default")
```

## 细粒度规则

`PermissionRule` 先用 glob 匹配工具名，再选择性匹配相关参数：Bash 使用
`command`，Read/Write/Edit/MultiEdit 使用 `file_path`，Glob/Grep 使用
`pattern`。匹配区分大小写，第一个匹配项生效。直接传给
`codeagent_client(rules=)` 的规则排在设置文件规则之前。

设置中的数组按 `allow`、`deny`、`ask` 顺序转换。请避免模式重叠：deny
项不会 自动优先于更早的 allow
项。规则只会在逐工具策略和能力策略之后到达，而且读取
快速路径不会进入这里。

``` json
{
  "permissions": {
    "allow": ["Bash(git status)", "Read(*)"],
    "deny":  ["Bash(rm -rf *)"],
    "ask":   ["Write(*)"],
    "defaultMode": "default"
  }
}
```

## 公开签名与默认值

``` r

PermissionRule(
  tool_name,
  behavior = c("allow", "deny", "ask"),
  source = "session",
  rule_content = NULL
)

check_permission(
  tool_name,
  mode = "default",
  rules = list(),
  tool_input = NULL
)

install_permission_gate(
  chat,
  permission_mode = "default",
  rules = list(),
  tools = list(),
  ask_fn = NULL,
  tool_meta = list()
)

codeagent_client(
  chat = NULL,
  permission_mode = "default",
  rules = list(),
  cwd = getwd(),
  max_turns = 100L,
  btw_groups = NULL,
  worktree_isolation = FALSE,
  verify_fn = NULL,
  mcp_config = NULL,
  register_tools = TRUE,
  data_shield = NULL,
  max_budget_usd = NULL
)
```

[`install_permission_gate()`](https://kaipingyang.github.io/codeagent/reference/install_permission_gate.md)
用于把中央权限门附加到现有的
[`ellmer::Chat`](https://ellmer.tidyverse.org/reference/Chat.html)。
`tools` 与 `settings$tools` 一样采用 `sets` / `capabilities` /
`overrides` 结构； `tool_meta` 是带名称的“工具到能力”列表。正常使用
codeagent 时，
[`codeagent_client()`](https://kaipingyang.github.io/codeagent/reference/codeagent_client.md)
会加载设置并安装权限门。

## 交互式审批

在 `default` 模式下，当调用解析为 `ask` 时，Shiny 应用会在输入框上方显示
Allow/Deny 审批条；promise 解析后才恢复执行。CLI
使用同步控制台提示。审批 失败、拒绝或缺少 `ask_fn`
都会导致拒绝。`AskUserQuestion` 使用独立的异步问题条
暂停并等待澄清答案。

## Hook 与参数重写

`PreToolUse`
不负责权限门的初始决策。它在权限门授权后（因此也在可能的人类审批
之后）、工具执行前，于工具包装层中运行一次。它可以拒绝调用或返回
`updatedInput`；重写后的参数会再次按照当前权限策略和 Data Shield
检查，此时若 结果为 `ask`
而没有第二条审批路径，则会拒绝。权限门拒绝时触发
`PermissionDenied`，执行后由 `on_tool_result` 触发 `PostToolUse`。

因此，`PreToolUse` 的否决仍能阻止执行，但不能阻止审批提示先显示。

## 危险审批与纵深防御

如果操作员批准
`Bash: rm -rf ./data`，仅凭批准并不能证明操作安全。各否决层的 时机不同：

| 层 | 时机与限制 |
|----|----|
| `settings$tools$overrides` deny | 在提示前拒绝；适合无条件的逐工具策略，包括读取工具 |
| deny `PermissionRule` | 在到达回退规则求值时于提示前拒绝；更高优先级策略和读取快速路径会绕过它 |
| 返回 block 的 Data Shield 入口/工具策略 | 在读取快速路径和提示之前运行 |
| 返回 deny 的 `PreToolUse` | 在权限门/人类授权之后、工具执行之前运行 |

这些控制属于基于语法或策略的纵深防御。例如，`Bash(rm -rf *)`
无法捕获通过
`RunR`、`unlink(..., recursive = TRUE)`、其他破坏性命令、运行时字符串拼接，
或“先写脚本再执行”的两个调用所实现的等价行为。

针对操作意图的语义审查器可以提高门槛，但仍依赖模型。采用只读或限定可写挂载
的完整操作系统级沙箱，可以不依赖命令拼写来执行边界；当前可移植的
[`shield_sandbox()`](https://kaipingyang.github.io/codeagent/reference/shield_sandbox.md)
policy 后端并不是这种内核强制适配器。整理跨语言破坏性操作
策略仍是开放设计问题，而不是已实现的安全保证。
