# Configuration

**Language:** English \|
[简体中文](https://kaipingyang.github.io/codeagent/articles/configuration-cn.md)

This article describes the configuration that the current source
actually consumes. All chunks are non-evaluating because examples may
require local credentials, providers, or files.

## Configuration locations

Create a user or project file with:

``` r

use_codeagent_settings(scope = "user")
use_codeagent_settings(scope = "project")
```

User scope is `<config-dir>/settings.json`, where `<config-dir>` is:

1.  `CODEAGENT_HOME`, when set;
2.  `rappdirs::user_config_dir("codeagent")`, when `rappdirs` is
    installed; or
3.  legacy `~/.codeagent` as a fallback.

On first use, codeagent attempts a one-time copy from legacy
`~/.codeagent` to the OS-standard directory. If migration cannot be
completed, the existing legacy directory remains usable. Project scope
is always `.codeagent/settings.json` under the current working
directory.

## Resolution order

The effective sequence is:

1.  start with package defaults;
2.  deep-merge user `settings.json`;
3.  deep-merge project `.codeagent/settings.json`;
4.  export the merged JSON `env` block with
    [`Sys.setenv()`](https://rdrr.io/r/base/Sys.setenv.html);
5.  read recognized environment-variable overrides;
6.  derive permission rules and load project instruction files.

The project JSON therefore wins over user JSON. An `env` entry is
exported before the environment layer is read and overwrites an
already-set variable of the same name in the current process. A process
environment variable wins over top-level JSON only when the merged `env`
block does not replace it.

Under `--vanilla`,
[`load_settings()`](https://kaipingyang.github.io/codeagent/reference/load_settings.md)
also imports previously unset `CODEAGENT_*` values from `~/.Renviron`.
That fallback occurs after model and endpoint fields have already been
resolved for the current load, so put `CODEAGENT_BASE_URL` and
`CODEAGENT_MODEL` in the JSON `env` block when relying on automatic CLI
construction. Credentials are read lazily and can remain in
`~/.Renviron` or another secret-injection mechanism.

## A functional settings example

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

Use snake_case for fields consumed directly by the R implementation. In
particular, `effort_level` is passed to
`ellmer::params(reasoning_effort = ...)`; camelCase `effortLevel` may be
retained in the loaded list but is not used by the automatic Chat
factory.

Important defaults include:

| Setting | Default | Meaning |
|----|----|----|
| `provider` | `NULL` | Use `openai_compatible` when `base_url` exists; otherwise use `anthropic`. |
| `model` | `NULL` | Provider-dependent: native ellmer providers may choose their own default; OpenAI-compatible endpoints normally need JSON, `CODEAGENT_MODEL`, or an explicit Chat. |
| `max_turns` | `100L` | Loop limit; normally choose it with a constructor/config argument. |
| `model_limit` | dynamic, fallback 200,000 | Context window derived from model/provider unless overridden. |
| `max_output_tokens` | `8192L` | Stored output-token setting. |
| `max_budget_usd` | `NULL` | No dollar cap. |
| `permission_mode` | `"default"` | Base loader value; see constructor precedence below. |
| `sandbox` | disabled, network allowed | Best-effort Bash/RunR defense in depth. |
| `file_tools` | `"core"` | Core tools; alternatives are `"btw"` and `"both"`. |
| `midloop_compact` | `TRUE` | Cheap near-limit tool-result snipping between rounds. |
| `midloop_full_compact` | `FALSE` | Do not make a blocking full compaction call mid-stream. |
| `explore_data` | `TRUE` | Register the read-only `ExploreData` tool. |
| `rag` | `FALSE` | Do not build/use codebase RAG. |
| `inject_r_env` | `FALSE` | Do not inject `.GlobalEnv` object summaries. |
| `auto_continue` | `FALSE` | Start a fresh Shiny conversation. |
| `web_citations` | `"off"` | Deterministic Shiny citation presentation is opt-in. |

## Constructor arguments override loaded values

[`codeagent_client()`](https://kaipingyang.github.io/codeagent/reference/codeagent_client.md)
always writes its `permission_mode`, `max_turns`, `btw_groups`,
`worktree_isolation`, `verify_fn`, and `mcp_config` arguments into the
live settings. Because those arguments have defaults, use the
constructor to choose these values rather than relying on similarly
named JSON or environment entries:

``` r

client <- codeagent_client(
  permission_mode = "accept_edits",
  max_turns = 50L,
  btw_groups = c("docs", "git", "pkg"),
  worktree_isolation = TRUE,
  max_budget_usd = 2.50
)
```

`max_budget_usd = NULL` is the exception: it preserves a positive value
loaded from `max_budget_usd` or `CODEAGENT_MAX_BUDGET_USD`. The cap is
checked through `chat$get_cost()` and can trigger only when ellmer has
pricing for the active provider/model.

`permissions.defaultMode` is not mapped to the constructor’s mode. The
`permissions.allow`, `deny`, and `ask` arrays are functional: they are
converted to ordered `PermissionRule` objects, and caller-supplied
`rules` are prepended.

## Environment variables

The current implementation uses these variables directly:

| Variable | Current use |
|----|----|
| `CODEAGENT_HOME` | Override the user configuration directory. |
| `CODEAGENT_BASE_URL` | OpenAI-compatible endpoint and compact-model backend selection. |
| `CODEAGENT_MODEL` | Active/default model and the `main` tier. |
| `CODEAGENT_HEAVY_MODEL` | `heavy` model alias; not selected automatically. |
| `CODEAGENT_FAST_MODEL` | `fast` alias and preferred compaction/classification/reviewer model. |
| `CODEAGENT_API_KEY` | Default credential read by OpenAI-compatible and several hosted-provider factories. |
| `CODEAGENT_MAX_BUDGET_USD` | Positive dollar-cost cap. |
| `CODEAGENT_MODEL_LIMIT` | Value loaded into `settings$model_limit`; dynamic context logic may use its own resolution. |
| `CODEAGENT_MAX_CONTEXT_TOKENS` | Highest-priority raw context-window override. |
| `CODEAGENT_AUTO_COMPACT_WINDOW` | Cap the window used to calculate compaction thresholds. |
| `CODEAGENT_DISABLE_COMPACT` | Any non-empty value disables automatic threshold compaction. |
| `CODEAGENT_EMBED_MODEL` | Embedding model for opt-in RAG. |

`CODEAGENT_PERMISSION_MODE` and `CODEAGENT_MAX_TURNS` are read by
[`load_settings()`](https://kaipingyang.github.io/codeagent/reference/load_settings.md),
but the default arguments of
[`codeagent_client()`](https://kaipingyang.github.io/codeagent/reference/codeagent_client.md)
overwrite them. Pass `permission_mode` and `max_turns` explicitly for a
client. Provider-native `ellmer` constructors may also use their own
variables, such as `ANTHROPIC_API_KEY`, AWS credentials, or OAuth state.

## API keys and setup

Do not put API keys in `settings.json` or a tracked project file. Prefer
a deployment secret or `~/.Renviron`. A keyring entry is not read
automatically by the current Chat factory; use an `apiKeyHelper` or host
integration that retrieves it and supplies the environment variable:

``` ini
CODEAGENT_API_KEY=your-token
```

`apiKeyHelper` or `api_key_helper` may name a command whose first output
line is used as `CODEAGENT_API_KEY` when that variable is absent:

``` json
{
  "apiKeyHelper": "secret-tool lookup service codeagent"
}
```

[`use_codeagent_setup()`](https://kaipingyang.github.io/codeagent/reference/use_codeagent_setup.md)
is interactive, but its current implementation includes a detected or
newly supplied provider key in the generated JSON `env` block before it
offers keyring/`~/.Renviron` persistence choices. Storing a value in the
keyring does not by itself wire retrieval into the automatic Chat
factory; configure an `apiKeyHelper`/host integration for that path. For
keyed providers, prefer
[`use_codeagent_settings()`](https://kaipingyang.github.io/codeagent/reference/use_codeagent_settings.md)
and add the credential separately. If you use the wizard, inspect and
remove any credential from the generated JSON immediately.

## Permission rules

Patterns without parentheses match a whole tool. Parenthesized content
matches the tool’s primary argument with `*` wildcards:

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

Content matching is implemented for `Bash`, `Read`, `Write`, `Edit`,
`MultiEdit`, `Glob`, and `Grep`. Rules are case-sensitive and first
match wins. In `plan` mode, non-read tools are denied before rules are
considered.

## Sandbox settings

``` json
{
  "sandbox": {
    "enabled": true,
    "allow_network": false,
    "keep_env": ["PATH", "HOME", "LANG", "TMPDIR"]
  }
}
```

When enabled, Bash receives only `keep_env`. Network denial uses an OS
network namespace where available and otherwise degrades, with a
warning, to command pattern blocking. `RunR` uses a scrubbed `callr`
child and timeout when `callr` is installed; without it, execution
remains in-process after pattern checks. This is not a complete
filesystem sandbox.

## Project `codeagent.md`

[`codeagent_client_config()`](https://kaipingyang.github.io/codeagent/reference/codeagent_client_config.md)
searches, in order, `.codeagent/config.md` and `codeagent.md` in `cwd`,
then the literal user fallback `~/.codeagent/config.md`. (This fallback
does not follow `CODEAGENT_HOME` or the OS-standard settings directory.)
The YAML front matter supports `client`, `btw_groups`,
`permission_mode`, and `max_turns`. The Markdown body is appended to the
system prompt.

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

Recognized prefixed client specs are `openai/<model>`,
`anthropic/<model>`, and `ollama/<model>`. `openai/<model>` uses
`chat_openai_compatible()` when `CODEAGENT_BASE_URL` is set; without a
base URL it falls through to the normal automatic provider path. A plain
model name uses
[`load_settings()`](https://kaipingyang.github.io/codeagent/reference/load_settings.md)
and
[`.make_chat()`](https://kaipingyang.github.io/codeagent/reference/dot-make_chat.md).
In a non-interactive session, omitting `alias` selects the first alias;
in an interactive session it opens a menu.

Create a template with:

``` r

use_codeagent_md()
```

## Project instructions

In addition to settings, codeagent loads instruction files from the user
and up to five directory levels from `cwd`: `CLAUDE.md`, `btw.md`,
`AGENTS.md`, and `llms.txt`. Outer files are included before more
specific inner files. A line consisting only of `@path/to/file` imports
that file, with cycle detection and a maximum import depth of five.
