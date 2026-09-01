# 配置（简体中文）

**语言：**
[English](https://kaipingyang.github.io/codeagent/articles/configuration.md)
\| 简体中文

本文描述当前源代码实际使用的配置。所有代码块都不会执行，因为示例可能
需要本地凭据、供应商或文件。

## 配置位置

使用以下函数创建用户级或项目级文件：

``` r

use_codeagent_settings(scope = "user")
use_codeagent_settings(scope = "project")
```

用户级位置为 `<config-dir>/settings.json`，其中 `<config-dir>`
按以下顺序 确定：

1.  如果设置了 `CODEAGENT_HOME`，使用该目录；
2.  如果安装了 `rappdirs`，使用
    `rappdirs::user_config_dir("codeagent")`；
3.  否则回退到旧版 `~/.codeagent`。

首次使用时，codeagent 会尝试把旧版 `~/.codeagent` 一次性复制到操作系统
标准目录。如果迁移无法完成，现有旧版目录仍可使用。项目级位置始终是当前
工作目录下的 `.codeagent/settings.json`。

## 解析顺序

有效的处理顺序为：

1.  从包默认值开始；
2.  深度合并用户级 `settings.json`；
3.  深度合并项目级 `.codeagent/settings.json`；
4.  用 [`Sys.setenv()`](https://rdrr.io/r/base/Sys.setenv.html)
    导出合并后 JSON 的 `env` 块；
5.  读取可识别的环境变量覆盖；
6.  派生权限规则并加载项目指令文件。

因此，项目 JSON 的优先级高于用户 JSON。`env` 条目会在读取环境变量层之前
导出，并覆盖当前进程中同名的已有变量。只有当合并后的 `env` 块没有替换
某个进程环境变量时，该变量才会覆盖顶层 JSON。

在 `--vanilla`
下，[`load_settings()`](https://kaipingyang.github.io/codeagent/reference/load_settings.md)
还会从 `~/.Renviron` 导入此前未设置的 `CODEAGENT_*`
值。这个后备步骤发生在当前加载已经解析模型和端点字段之后， 因此如果依赖
CLI 自动构造，请把 `CODEAGENT_BASE_URL` 和 `CODEAGENT_MODEL` 放在 JSON
的 `env` 块中。凭据采用延迟读取，可以继续 放在 `~/.Renviron`
或其他密钥注入机制中。

## 一个可实际生效的设置示例

``` json
{
  "provider": "openai_compatible",
  "model": "main",
  "env": {
    "CODEAGENT_BASE_URL": "https://YOUR-WORKSPACE/serving-endpoints",
    "CODEAGENT_MODEL": "your-main-endpoint-name",
    "CODEAGENT_HEAVY_MODEL": "your-heavy-endpoint-name",
    "CODEAGENT_FAST_MODEL": "your-fast-endpoint-name"
  },
  "permissions": {
    "allow": ["Read", "Bash(R CMD check *)"],
    "deny": ["Bash(rm -rf *)"],
    "ask": ["Write"]
  },
  "sandbox": {
    "enabled": false,
    "allow_network": true
  },
  "effort_level": "high",
  "file_tools": "core",
  "midloop_compact": true,
  "midloop_full_compact": false,
  "explore_data": true,
  "auto_continue": false,
  "web_citations": "off",
  "max_budget_usd": null
}
```

对于 R 实现直接使用的字段，请使用 snake_case。特别是，`effort_level`
会传给 `ellmer::params(reasoning_effort = ...)`；camelCase 的
`effortLevel` 可能保留在加载后的列表中，但自动 Chat 工厂不会使用它。

重要默认值包括：

| 设置 | 默认值 | 含义 |
|----|----|----|
| `provider` | `NULL` | 存在 `base_url` 时使用 `openai_compatible`，否则使用 `anthropic`。 |
| `model` | `NULL` | 取决于供应商：ellmer 原生供应商可选择自身默认模型；OpenAI 兼容端点通常需要 JSON、`CODEAGENT_MODEL` 或显式 Chat。 |
| `max_turns` | `100L` | 循环上限；通常通过构造函数/配置参数选择。 |
| `model_limit` | 动态，后备值 200,000 | 从模型/供应商推导上下文窗口，除非被覆盖。 |
| `max_output_tokens` | `8192L` | 保存的输出 token 设置。 |
| `max_budget_usd` | `NULL` | 不设美元上限。 |
| `permission_mode` | `"default"` | 加载器基础值；参见下文的构造函数优先级。 |
| `sandbox` | 禁用，允许网络 | Bash/RunR 的尽力而为纵深防御。 |
| `file_tools` | `"core"` | 核心工具；也可设为 `"btw"` 或 `"both"`。 |
| `midloop_compact` | `TRUE` | 在轮次之间接近上限时进行低成本工具结果裁剪。 |
| `midloop_full_compact` | `FALSE` | 不在流式处理中途执行阻塞式完整压缩调用。 |
| `explore_data` | `TRUE` | 注册只读的 `ExploreData` 工具。 |
| `rag` | `FALSE` | 不构建/使用代码库 RAG。 |
| `inject_r_env` | `FALSE` | 不注入 `.GlobalEnv` 对象摘要。 |
| `auto_continue` | `FALSE` | 启动新的 Shiny 对话。 |
| `web_citations` | `"off"` | 确定性 Shiny 引用展示需要显式启用。 |

## 构造函数参数覆盖已加载值

[`codeagent_client()`](https://kaipingyang.github.io/codeagent/reference/codeagent_client.md)
总会把自身的 `permission_mode`、`max_turns`、
`btw_groups`、`worktree_isolation`、`verify_fn` 和 `mcp_config` 参数写入
实时设置。由于这些参数都有默认值，应通过构造函数选择它们，而不要依赖
JSON 或环境中的同名条目：

``` r

client <- codeagent_client(
  permission_mode = "accept_edits",
  max_turns = 50L,
  btw_groups = c("docs", "git", "pkg"),
  worktree_isolation = TRUE,
  max_budget_usd = 2.50
)
```

`max_budget_usd = NULL` 是例外：它会保留从 `max_budget_usd` 或
`CODEAGENT_MAX_BUDGET_USD` 加载的正值。上限通过 `chat$get_cost()` 检查，
只有 ellmer 拥有当前供应商/模型的价格时才可能触发。

`permissions.defaultMode` 不会映射到构造函数的模式。
`permissions.allow`、`deny` 和 `ask`
数组可以实际生效：它们会转换为有序的 `PermissionRule`
对象，而调用者提供的 `rules` 会添加到最前面。

## 环境变量

当前实现直接使用以下变量：

| 变量 | 当前用途 |
|----|----|
| `CODEAGENT_HOME` | 覆盖用户配置目录。 |
| `CODEAGENT_BASE_URL` | OpenAI 兼容端点和压缩模型后端选择。 |
| `CODEAGENT_MODEL` | 当前/默认模型和 `main` 层级。 |
| `CODEAGENT_HEAVY_MODEL` | `heavy` 模型别名；不会自动选择。 |
| `CODEAGENT_FAST_MODEL` | `fast` 别名，以及压缩/分类/reviewer 的首选模型。 |
| `CODEAGENT_API_KEY` | OpenAI 兼容和若干托管供应商工厂读取的默认凭据。 |
| `CODEAGENT_MAX_BUDGET_USD` | 正的美元成本上限。 |
| `CODEAGENT_MODEL_LIMIT` | 加载到 `settings$model_limit` 的值；动态上下文逻辑可能使用自身的解析过程。 |
| `CODEAGENT_MAX_CONTEXT_TOKENS` | 原始上下文窗口的最高优先级覆盖。 |
| `CODEAGENT_AUTO_COMPACT_WINDOW` | 限制用于计算压缩阈值的窗口。 |
| `CODEAGENT_DISABLE_COMPACT` | 任意非空值都会禁用自动阈值压缩。 |
| `CODEAGENT_EMBED_MODEL` | 可选 RAG 使用的嵌入模型。 |

[`load_settings()`](https://kaipingyang.github.io/codeagent/reference/load_settings.md)
会读取 `CODEAGENT_PERMISSION_MODE` 和 `CODEAGENT_MAX_TURNS`，但
[`codeagent_client()`](https://kaipingyang.github.io/codeagent/reference/codeagent_client.md)
的默认参数会覆盖它们。 请为客户端显式传入 `permission_mode` 和
`max_turns`。供应商原生的 `ellmer` 构造函数也可能使用自己的变量，例如
`ANTHROPIC_API_KEY`、AWS 凭据或 OAuth 状态。

## API 密钥和设置向导

不要把 API 密钥放入 `settings.json` 或被跟踪的项目文件。优先使用部署
密钥或 `~/.Renviron`。当前 Chat 工厂不会自动读取密钥环条目；若使用
密钥环，应通过 `apiKeyHelper` 或宿主集成读取并提供环境变量：

``` ini
CODEAGENT_API_KEY=your-token
```

`apiKeyHelper` 或 `api_key_helper` 可以指定一个命令；当该变量不存在时，
命令输出的第一行会用作 `CODEAGENT_API_KEY`：

``` json
{
  "apiKeyHelper": "secret-tool lookup service codeagent"
}
```

[`use_codeagent_setup()`](https://kaipingyang.github.io/codeagent/reference/use_codeagent_setup.md)
是交互式的，但其当前实现会先把检测到或新提供的 供应商密钥放入生成的 JSON
`env` 块，然后才提供密钥环/`~/.Renviron`
持久化选项。仅把值存入密钥环并不会自动把读取逻辑接入 Chat 工厂；该路径
仍需配置 `apiKeyHelper` 或宿主集成。对于需要密钥的供应商，请优先使用
[`use_codeagent_settings()`](https://kaipingyang.github.io/codeagent/reference/use_codeagent_settings.md)
并单独添加凭据。如果使用向导，请立即检查生成 的
JSON，并删除其中的任何凭据。

## 权限规则

不带括号的模式匹配整个工具。括号中的内容使用 `*` 通配符匹配工具的主要
参数：

``` json
{
  "permissions": {
    "allow": [
      "Read",
      "Bash(R CMD check *)"
    ],
    "deny": [
      "Bash(rm -rf *)"
    ],
    "ask": [
      "Write(/shared/*)"
    ]
  }
}
```

`Bash`、`Read`、`Write`、`Edit`、`MultiEdit`、`Glob` 和 `Grep` 实现了
内容匹配。规则区分大小写，并采用第一个匹配项。在 `plan` 模式中，非只读
工具会在考虑规则之前被拒绝。

## 沙箱设置

``` json
{
  "sandbox": {
    "enabled": true,
    "allow_network": false,
    "keep_env": ["PATH", "HOME", "LANG", "TMPDIR"]
  }
}
```

启用后，Bash 只会获得 `keep_env` 中的环境变量。在可用时，网络禁止使用
操作系统网络 namespace；否则会发出警告，并降级为命令模式阻止。安装了
`callr` 时，`RunR` 使用环境已清理且带超时的 `callr` 子进程；没有它时，
会在模式检查后继续于当前进程中执行。这不是完整的文件系统沙箱。

## 项目 `codeagent.md`

[`codeagent_client_config()`](https://kaipingyang.github.io/codeagent/reference/codeagent_client_config.md)
会依次在 `cwd` 中查找 `.codeagent/config.md` 和
`codeagent.md`，然后查找固定的用户后备路径
`~/.codeagent/config.md`。（该后备路径不跟随 `CODEAGENT_HOME` 或操作系统
标准设置目录。）YAML front matter 支持 `client`、`btw_groups`、
`permission_mode` 和 `max_turns`。Markdown 正文会附加到系统提示中。

``` yaml
---
client:
  gpt41:    openai/gpt-4.1
  local:    ollama/llama3.2
  sonnet:   anthropic/claude-sonnet-4-6
btw_groups: [docs, git, pkg]
permission_mode: default
max_turns: 50
---
Follow tidyverse style and run focused tests before the full suite.
```

``` r

client <- codeagent_client_config(alias = "gpt41")
```

可识别的带前缀客户端规格为 `openai/<model>`、`anthropic/<model>` 和
`ollama/<model>`。设置了 `CODEAGENT_BASE_URL` 时，`openai/<model>` 使用
`chat_openai_compatible()`；没有 base URL 时，它会回落到常规自动
供应商路径。纯模型名称使用
[`load_settings()`](https://kaipingyang.github.io/codeagent/reference/load_settings.md)
和
[`.make_chat()`](https://kaipingyang.github.io/codeagent/reference/dot-make_chat.md)。在非交互
会话中，省略 `alias` 会选择第一个别名；在交互会话中则会打开菜单。

使用以下函数创建模板：

``` r

use_codeagent_md()
```

## 项目指令

除设置外，codeagent 还会从用户级位置和从 `cwd` 向上的最多五层目录中加载
指令文件：`CLAUDE.md`、`btw.md`、`AGENTS.md` 和 `llms.txt`。外层文件先于
更具体的内层文件包含。仅由 `@path/to/file` 组成的行会导入该文件，并带有
循环检测和最大五层的导入深度限制。
