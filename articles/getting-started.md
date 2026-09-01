# Getting started with codeagent

**Language:** English \|
[简体中文](https://kaipingyang.github.io/codeagent/articles/getting-started-cn.md)

`codeagent` is an R-native coding-agent harness built on `ellmer` and
`btw`. It does not shell out to another coding-agent CLI. It supplies
tools, permissions, context compaction, hooks, skills, sessions, and
multi-agent coordination, and exposes them through R, a terminal REPL,
and a Shiny app.

All code chunks in this article require a configured model and are not
evaluated when the vignette is built.

## Installation

Install the package and its pinned dependencies from GitHub:

``` r

pak::pak("kaipingyang/codeagent")

# Recommended to ensure the verified development build of the optional btw tools
pak::pak("posit-dev/btw@d11591b09d9127b05d673e8c96569d2bbae2ec44")
```

The command-line launcher requires the optional `Rapp` package and is a
separate, one-time installation step:

``` r

# Needed only if Rapp was not installed with optional dependencies
pak::pak("r-lib/Rapp@489655f24945042791ddb083d0d5518c4a905d9f")

codeagent::install_codeagent_cli()
```

## Configure an endpoint

The safest scaffold is
[`use_codeagent_settings()`](https://kaipingyang.github.io/codeagent/reference/use_codeagent_settings.md).
User-scope settings are written to codeagent’s OS-standard configuration
directory (or `CODEAGENT_HOME` when set); legacy `~/.codeagent` content
is migrated or used as a fallback. Project settings are written to
`.codeagent/settings.json`.

``` r

codeagent::use_codeagent_settings(scope = "user")
```

For an OpenAI-compatible endpoint, keep endpoint and model names in the
`env` block, but keep credentials out of JSON:

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

Store the credential in `~/.Renviron` or another mechanism that injects
it into the process environment:

> A keyring entry is not read automatically by the current Chat factory.
> To use a keyring, configure an `apiKeyHelper` (see the configuration
> article) or a host integration that retrieves the secret and supplies
> `CODEAGENT_API_KEY`.

``` ini
CODEAGENT_API_KEY=your-token
```

The merged settings `env` block is applied with
[`Sys.setenv()`](https://rdrr.io/r/base/Sys.setenv.html) before
recognized model settings are read. This makes endpoint and model
configuration work in the `--vanilla` CLI launcher. A
`CODEAGENT_API_KEY` line in `~/.Renviron` is also imported as a fallback
before credentials are used. Never commit either file when it contains
real infrastructure details or credentials.

You can bypass automatic construction and supply any configured
[`ellmer::Chat`](https://ellmer.tidyverse.org/reference/Chat.html)
directly. This is often the clearest route for provider-native
authentication:

``` r

chat <- ellmer::chat_openai_compatible(
  base_url = Sys.getenv("CODEAGENT_BASE_URL"),
  model = Sys.getenv("CODEAGENT_MODEL"),
  credentials = function() Sys.getenv("CODEAGENT_API_KEY")
)
```

## Build a client

With settings configured, build the harness automatically:

``` r

library(codeagent)
client <- codeagent_client()
```

Or wrap the explicit Chat created above:

``` r

client <- codeagent_client(
  chat,
  permission_mode = "default"
)
```

[`codeagent_client()`](https://kaipingyang.github.io/codeagent/reference/codeagent_client.md)
rebuilds the system prompt and, by default, registers the core file and
shell tools, web tools, `RunR`, memory, linting, tasks, notebooks, data
exploration, skills, an agent tool, and the selected `btw` groups. Tool
availability can depend on optional packages. All tools pass through one
central permission gate. Set `register_tools = FALSE` only when a host
will register them later, as the Shiny lazy-start path does.

## Run a one-shot query

``` r

codeagent(client, "List the .R files in R/ and summarize their roles")
```

[`codeagent()`](https://kaipingyang.github.io/codeagent/reference/codeagent.md)
submits one prompt to the client’s Chat. `ellmer` runs any multi-round
tool calls, and codeagent applies its input/output Data Shield gates and
optional deterministic citation transform. The Chat retains history, so
a second call is a follow-up. This lightweight one-shot path is not the
complete REPL/Shiny turn pipeline: automatic session saving, per-turn
compaction, reminders, and lifecycle handling live in
[`codeagent_console()`](https://kaipingyang.github.io/codeagent/reference/codeagent_console.md),
`codeagent_stream*()`, and
[`agent_loop()`](https://kaipingyang.github.io/codeagent/reference/agent_loop.md).

## Use the terminal REPL

From R:

``` r

codeagent_console(client)
```

Or, after
[`install_codeagent_cli()`](https://kaipingyang.github.io/codeagent/reference/install_codeagent_cli.md):

``` bash
codeagent             # interactive REPL, default permission mode
codeagent -y          # interactive REPL, bypass permission mode
codeagent "query"     # one-shot query
codeagent -p "query"  # explicit non-interactive print mode
codeagent -p "query" -o json
```

The REPL reuses one client, streams by default when launched from R,
compacts long conversations, and saves sessions. Current built-in
commands include `/model`, `/compact`, `/clear`, `/rewind`, `/sessions`,
`/budget`, `/cost`, `/copy`, `/export`, `/context`, `/help`, and
`/exit`; any other `/<name>` is handled as a skill invocation. The
launcher also provides `app`, `sessions`, `skills`, `mcp`, and `info`
subcommands.

## Launch the Shiny app

For local, single-user use:

``` r

codeagent_app(client, theme = "default")
```

A bare Chat is treated as a template and cloned into a fresh client per
Shiny session. For a multi-user deployment, create all mutable state in
a factory:

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

The default `ui_layout = "classic"` provides chat plus the Output /
Files / File workspace. `ui_layout = "page_chat"` opts into the
full-window layout. Tools and skills initialize after the first UI
flush; input remains disabled until they are ready. Type `/` for local
commands and the skill typeahead.

## Choose a permission mode

| Mode | Current behavior |
|----|----|
| `default` | Read-only tools and recognized read-only Bash commands auto-allow; other writes and execution ask. |
| `plan` | Read-only tools allow; mutating tools deny. |
| `accept_edits` | `Write`, `Edit`, and `MultiEdit` auto-allow; other non-read operations still ask. |
| `bypass` | Tool calls auto-allow. Use only in a trusted environment. |
| `dont_ask` | Read-only tools allow; calls that would ask are denied. |
| `auto` | A model classifier returns allow or deny; failures fall back to ask. |
| `bubble` | Sub-agent decisions return ask so the parent can resolve them. |

Constructor arguments are the reliable way to choose the mode:

``` r

client <- codeagent_client(chat, permission_mode = "accept_edits")
```

Rules are evaluated in order before most mode defaults and can match a
tool’s main argument:

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

Equivalent JSON patterns belong in `permissions.allow`,
`permissions.deny`, and `permissions.ask`, for example
`"Bash(R CMD build *)"`.

## Understand sandboxing

The default is:

``` json
{ "sandbox": { "enabled": false, "allow_network": true } }
```

When enabled, Bash receives a reduced environment and runs in the
configured working directory. With `allow_network = false`, codeagent
blocks known network commands and uses `unshare -Urn` for kernel-level
network isolation when the host supports unprivileged namespaces. If
`unshare` is unavailable, it warns and falls back to a bypassable
command-name blacklist.

`RunR` uses a separate `callr` process with a scrubbed environment and a
30-second timeout when both sandboxing and `callr` are available.
Otherwise it runs in-process after pattern checks. This sandbox is
defense in depth, not a complete filesystem or process security
boundary; use containers or another OS sandbox for untrusted workloads.

## Run multi-agent work

``` r

# Fixed fan-out
team_run(c("review R/a.R", "review R/b.R"))

# Work-stealing over a shared SQLite board
team_coordinate(c("task 1", "task 2", "task 3", "task 4"))

# LLM-led decomposition and replanning
team_lead("Refactor the parser and add tests", max_rounds = 3)
```

## Where to go next

- Read
  [`vignette("configuration", package = "codeagent")`](https://kaipingyang.github.io/codeagent/articles/configuration.md)
  for settings, environment variables, and project configuration.
- Read
  [`vignette("models", package = "codeagent")`](https://kaipingyang.github.io/codeagent/articles/models.md)
  for providers, model tiers, switching, reasoning, and pricing.
- See
  [`?codeagent_client`](https://kaipingyang.github.io/codeagent/reference/codeagent_client.md),
  [`?codeagent_console`](https://kaipingyang.github.io/codeagent/reference/codeagent_console.md),
  and
  [`?codeagent_app`](https://kaipingyang.github.io/codeagent/reference/codeagent_app.md)
  for the public API.
