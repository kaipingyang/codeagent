# codeagent 入门（简体中文）

**语言：**
[English](https://kaipingyang.github.io/codeagent/articles/getting-started.md)
\| 简体中文

`codeagent` 是一个基于 `ellmer` 和 `btw` 构建的 R 原生编码智能体
harness。它不会通过 shell 调用另一个编码智能体 CLI，而是自行提供工具、
权限、上下文压缩、hooks、skills、会话和多智能体协调，并通过 R、终端 REPL
和 Shiny 应用提供这些能力。

本文中的所有代码块都需要已配置的模型，因此构建 vignette 时不会执行。

## 安装

从 GitHub 安装本包及其固定版本的依赖：

``` r

pak::pak("kaipingyang/codeagent")

# Recommended to ensure the verified development build of the optional btw tools
pak::pak("posit-dev/btw@d11591b09d9127b05d673e8c96569d2bbae2ec44")
```

命令行启动器需要可选的 `Rapp` 包，并且需要单独执行一次安装：

``` r

# Needed only if Rapp was not installed with optional dependencies
pak::pak("r-lib/Rapp@489655f24945042791ddb083d0d5518c4a905d9f")

codeagent::install_codeagent_cli()
```

## 配置端点

最安全的脚手架函数是
[`use_codeagent_settings()`](https://kaipingyang.github.io/codeagent/reference/use_codeagent_settings.md)。用户级设置会写入
codeagent 的操作系统标准配置目录（如果设置了 `CODEAGENT_HOME`，则写入
该目录）；旧版 `~/.codeagent` 内容会迁移，或在需要时作为后备目录。
项目级设置会写入 `.codeagent/settings.json`。

``` r

codeagent::use_codeagent_settings(scope = "user")
```

对于 OpenAI 兼容端点，把端点和模型名称放在 `env` 块中，但不要把凭据 放入
JSON：

``` json
{
  "provider": "openai_compatible",
  "model": "main",
  "env": {
    "CODEAGENT_BASE_URL": "https://YOUR-WORKSPACE/serving-endpoints",
    "CODEAGENT_MODEL": "your-main-endpoint",
    "CODEAGENT_HEAVY_MODEL": "your-heavy-endpoint",
    "CODEAGENT_FAST_MODEL": "your-fast-endpoint"
  },
  "permissions": {
    "allow": [],
    "deny": [],
    "ask": []
  }
}
```

把凭据存放在 `~/.Renviron`，或通过其他机制注入进程环境：

> 当前 Chat 工厂不会自动读取密钥环条目。若要使用密钥环，请配置
> `apiKeyHelper`（参见配置文章），或由宿主集成读取密钥并提供
> `CODEAGENT_API_KEY`。

``` ini
CODEAGENT_API_KEY=your-token
```

合并后的设置 `env` 块会先通过
[`Sys.setenv()`](https://rdrr.io/r/base/Sys.setenv.html)
应用，然后才读取可识别的 模型设置。因此，端点和模型配置在使用
`--vanilla` 的 CLI 启动器中也能 生效。`~/.Renviron` 中的
`CODEAGENT_API_KEY` 行也会在凭据被使用前作为
后备导入。含有真实基础设施信息或凭据时，绝不要提交这两个文件中的任何
一个。

你也可以绕过自动构造，直接提供任意已配置的
[`ellmer::Chat`](https://ellmer.tidyverse.org/reference/Chat.html)。对于供应商
原生认证，这通常是最清晰的方式：

``` r

chat <- ellmer::chat_openai_compatible(
  base_url = Sys.getenv("CODEAGENT_BASE_URL"),
  model = Sys.getenv("CODEAGENT_MODEL"),
  credentials = function() Sys.getenv("CODEAGENT_API_KEY")
)
```

## 构建客户端

完成设置后，可以自动构建 harness：

``` r

library(codeagent)
client <- codeagent_client()
```

也可以包装上面显式创建的 Chat：

``` r

client <- codeagent_client(
  chat,
  permission_mode = "default"
)
```

[`codeagent_client()`](https://kaipingyang.github.io/codeagent/reference/codeagent_client.md)
会重建系统提示，并默认注册核心文件和 shell 工具、 Web
工具、`RunR`、记忆、lint、任务、notebook、数据探索、skills、智能体
工具以及选定的 `btw` 工具组。工具是否可用可能取决于可选包。所有工具都
通过同一个中央权限门。只有当宿主稍后会自行注册工具时，才应设置
`register_tools = FALSE`；Shiny 的延迟启动路径就是这样做的。

## 运行一次性查询

``` r

codeagent(client, "List the .R files in R/ and summarize their roles")
```

[`codeagent()`](https://kaipingyang.github.io/codeagent/reference/codeagent.md)
会向客户端的 Chat 提交一个提示。`ellmer` 运行任何多轮工具
调用，codeagent 则应用输入/输出 Data Shield 门和可选的确定性引用转换。
Chat 会保留历史记录，因此第二次调用会成为后续对话。这个轻量的一次性
路径并不是完整的 REPL/Shiny 轮次流水线：自动保存会话、逐轮压缩、提醒和
生命周期处理位于
[`codeagent_console()`](https://kaipingyang.github.io/codeagent/reference/codeagent_console.md)、`codeagent_stream*()`
和
[`agent_loop()`](https://kaipingyang.github.io/codeagent/reference/agent_loop.md)
中。

## 使用终端 REPL

从 R 中启动：

``` r

codeagent_console(client)
```

或者在运行
[`install_codeagent_cli()`](https://kaipingyang.github.io/codeagent/reference/install_codeagent_cli.md)
之后：

``` bash
codeagent             # interactive REPL, default permission mode
codeagent -y          # interactive REPL, bypass permission mode
codeagent "query"     # one-shot query
codeagent -p "query"  # explicit non-interactive print mode
codeagent -p "query" -o json
```

REPL 会复用同一个客户端；从 R 启动时默认流式输出，并压缩长对话和保存
会话。当前内置命令包括 `/model`、`/compact`、`/clear`、`/rewind`、
`/sessions`、`/budget`、`/cost`、`/copy`、`/export`、`/context`、
`/help` 和 `/exit`；其他任何 `/<name>` 都会作为 skill 调用处理。启动器
还提供 `app`、`sessions`、`skills`、`mcp` 和 `info` 子命令。

## 启动 Shiny 应用

用于本地单用户场景：

``` r

codeagent_app(client, theme = "default")
```

裸 Chat 会被视为模板，并在每个 Shiny 会话中克隆为一个新的客户端。
对于多用户部署，应在工厂函数中创建所有可变状态：

``` r

codeagent_app(client_factory = function(session) {
  codeagent_client(
    ellmer::chat_openai_compatible(
      base_url = Sys.getenv("CODEAGENT_BASE_URL"),
      model = Sys.getenv("CODEAGENT_MODEL"),
      credentials = function() Sys.getenv("CODEAGENT_API_KEY")
    ),
    register_tools = FALSE
  )
})
```

默认的 `ui_layout = "classic"` 提供聊天以及 Output / Files / File
工作区。 `ui_layout = "page_chat"` 会启用全窗口布局。工具和 skills
在第一次 UI flush 后初始化；准备完成之前，输入会保持禁用。输入 `/`
可查看本地命令 和 skill 自动补全。

## 选择权限模式

| 模式 | 当前行为 |
|----|----|
| `default` | 只读工具和识别出的只读 Bash 命令自动允许；其他写入和执行会询问。 |
| `plan` | 允许只读工具；拒绝变更型工具。 |
| `accept_edits` | `Write`、`Edit` 和 `MultiEdit` 自动允许；其他非只读操作仍会询问。 |
| `bypass` | 工具调用自动允许。仅应在可信环境中使用。 |
| `dont_ask` | 允许只读工具；原本需要询问的调用会被拒绝。 |
| `auto` | 模型分类器返回允许或拒绝；失败时回退为询问。 |
| `bubble` | 子智能体的决策返回询问，由父智能体解决。 |

构造函数参数是选择模式的可靠方式：

``` r

client <- codeagent_client(chat, permission_mode = "accept_edits")
```

规则会按顺序在大多数模式默认值之前求值，并可匹配工具的主要参数：

``` r

client <- codeagent_client(
  chat,
  permission_mode = "default",
  rules = list(
    PermissionRule("Bash", "allow", rule_content = "R CMD build *"),
    PermissionRule("Bash", "deny", rule_content = "rm -rf *")
  )
)
```

等价的 JSON 模式应放在 `permissions.allow`、`permissions.deny` 和
`permissions.ask` 中，例如 `"Bash(R CMD build *)"`。

## 理解沙箱

默认值为：

``` json
{ "sandbox": { "enabled": false, "allow_network": true } }
```

启用后，Bash 会获得精简的环境，并在配置的工作目录中运行。当
`allow_network = false` 时，codeagent 会阻止已知网络命令，并在宿主支持
非特权 namespace 时使用 `unshare -Urn` 实现内核级网络隔离。如果
`unshare` 不可用，它会发出警告，并回退到可绕过的命令名称黑名单。

当沙箱和 `callr` 都可用时，`RunR` 会在环境已清理且有 30 秒超时的独立
`callr` 进程中运行。否则，它会在模式检查后于当前进程中运行。此沙箱是
纵深防御，不是完整的文件系统或进程安全边界；对于不可信工作负载，请使用
容器或其他操作系统级沙箱。

## 运行多智能体工作

``` r

# Fixed fan-out
team_run(c("review R/a.R", "review R/b.R"))

# Work-stealing over a shared SQLite board
team_coordinate(c("task 1", "task 2", "task 3", "task 4"))

# LLM-led decomposition and replanning
team_lead("Refactor the parser and add tests", max_rounds = 3)
```

## 后续阅读

- 阅读
  [`vignette("configuration", package = "codeagent")`](https://kaipingyang.github.io/codeagent/articles/configuration.md)，了解设置、环境
  变量和项目配置。
- 阅读
  [`vignette("models", package = "codeagent")`](https://kaipingyang.github.io/codeagent/articles/models.md)，了解供应商、模型层级、
  切换、推理和价格。
- 查看
  [`?codeagent_client`](https://kaipingyang.github.io/codeagent/reference/codeagent_client.md)、[`?codeagent_console`](https://kaipingyang.github.io/codeagent/reference/codeagent_console.md)
  和
  [`?codeagent_app`](https://kaipingyang.github.io/codeagent/reference/codeagent_app.md)，了解
  公共 API。
