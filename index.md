# codeagent

An R-native agentic coding assistant built on
[ellmer](https://ellmer.tidyverse.org) and [btw](https://btw.posit.co).
It reimplements a coding-agent **harness** in R: the agent loop,
permission system, context compaction, hook system, skill system, tool
execution, session management, multi-agent coordination, a CLI REPL, and
an interactive Shiny UI.

> **Not a wrapper.** codeagent reimplements the harness from scratch
> rather than shelling out to an external CLI.

## Installation

``` r

pak::pak(c("tidyverse/ellmer", "kaipingyang/codeagent"))

# Recommended: btw adds R-environment tools (docs, git, pkg, file editing, etc.)
# Without btw the agent has minimal tooling for real R projects.
pak::pak("posit-dev/btw")
```

## Configuration

### Step 1 — Create settings file

``` r

codeagent::use_codeagent_settings()   # creates ~/.codeagent/settings.json
```

Edit the generated file with your endpoint:

``` json
{
  "provider": "openai_compatible",
  "model": "main",
  "env": {
    "CODEAGENT_BASE_URL": "https://YOUR-WORKSPACE/serving-endpoints",
    "CODEAGENT_MODEL": "your-main-endpoint",
    "CODEAGENT_FAST_MODEL": "your-fast-endpoint",
    "CODEAGENT_API_KEY": "your-token"
  }
}
```

> `CODEAGENT_*` vars in the `env` block are loaded at startup even under
> `--vanilla`, so you do not need to set them separately in `.Renviron`.

### Step 2 — Install the CLI (once)

``` r

codeagent::install_codeagent_cli()   # puts `codeagent` on your PATH
```

``` bash
codeagent           # interactive REPL (default permission mode)
codeagent -y        # bypass mode (skip all permission prompts)
codeagent "query"   # one-shot query
```

## Quick start (R)

``` r

library(codeagent)

# Option A: auto-build client from settings.json
client <- codeagent_client()

# Option B: explicit ellmer Chat
chat   <- ellmer::chat_openai_compatible(
  base_url    = Sys.getenv("CODEAGENT_BASE_URL"),
  model       = Sys.getenv("CODEAGENT_MODEL"),
  credentials = function() Sys.getenv("CODEAGENT_API_KEY")
)
client <- codeagent_client(chat)

# One-shot query
codeagent(client, "List all .R files in R/")

# Interactive Shiny app
codeagent_app(client)

# Interactive CLI REPL
codeagent_console(client)
```

## Features

### Agent harness

| Feature | Details |
|----|----|
| **Agent loop** | [`agent_loop()`](https://kaipingyang.github.io/codeagent/reference/agent_loop.md) with max_turns, budget tracking, compaction |
| **Permissions** | 7 modes: `default`, `plan`, `accept_edits`, `bypass`, `dont_ask`, `auto`, `bubble`; fine-grained rules match tool arguments |
| **Hooks** | 12 lifecycle events (tool, permission, message, session), configurable from `settings.json` |
| **Compaction** | Dynamic per-model context window + two-level flow (session-memory summary → full 9-section summary), real token counts via `get_tokens()`, PTL/413 fallback, an “N% context left” indicator (REPL + Shiny), and **mid-loop compaction** between tool rounds |
| **System prompt** | Tone, task, convention, tool-use, and R-specific behavioural guidance |
| **Error recovery** | PTL/rate-limit/network/auth classification; exponential backoff |
| **Verification** | `verify_fn` param + [`verify_r_tests()`](https://kaipingyang.github.io/codeagent/reference/verify_r_tests.md) re-enters loop on test failures |
| **Plan mode** | Model enters/exits read-only planning mid-turn |
| **Rewind** | [`truncate_chat_turns()`](https://kaipingyang.github.io/codeagent/reference/truncate_chat_turns.md) / REPL `/rewind` roll the conversation back |
| **Model switch** | `switch_model(client, model)` swaps provider/model mid-session |

### Tools

| Group | Source | Tools |
|----|----|----|
| Core | codeagent | Bash, Read, Write, Edit, MultiEdit, Glob, Grep, LS |
| docs | btw | help pages, vignettes, NEWS |
| env | btw | describe data frames / R environment |
| files | btw | hash-anchored precise editing + atomic multi-file patch |
| git | btw | status, diff, log, commit, branches |
| pkg | btw | document, check, test, coverage, load_all |
| web | btw | URL → Markdown |
| agent | btw | hierarchical subagent delegation |
| data | codeagent | `ExploreData` — sandboxed data.frame queries; `DescribeData` — strict protected-data metadata (Data Shield) |

### Data Shield (opt-in)

``` r

# Easy declaration: creates a private R6 engine for this client.
client <- codeagent_client(chat, data_shield = list(
  shield_describe(k_anon = 5),
  shield_egress(max_rows = 0, on_fail = "redact"),
  shield_regex(on_fail = "redact"),
  shield_ingress(on_fail = "ask"),
  shield_tool_policy(rules = list(
    KMPlot = list(ingress = "scan", egress = "bypass")
  )),
  shield_sandbox(project_root = getwd(), backend = "policy"),
  shield_reviewer(model = Sys.getenv("CODEAGENT_FAST_MODEL"), on_risk = "ask")
))

# Explicit lifecycle for uploaded data / shared threads.
shield <- DataShield$new(
  strategies = list(shield_describe(), shield_egress(max_rows = 0)))
shield$register_data(df, name = "study")
# Column-level raw override for public-dictionary columns (reason required):
shield$register_data(vs, name = "vs",
  column_access = list(TESTCD = list(prompt = "raw", egress = "raw",
                                     reason = "SDTM public codelist")))
client <- codeagent_client(chat, data_shield = shield)
```

Data Shield never sends raw rows through `DescribeData`; bulk tool
output and registered high-entropy values are withheld before reaching
the LLM. Foreground `Agent` sub-chats inherit the same shield;
cross-process `BackgroundAgent`/`/bg` fail closed while a shield is
active.

`shield_egress(max_rows = 0)` retains **no raw tabular line** when bulk
output is detected; scalar/status/model-summary output still passes.
[`shield_regex()`](https://kaipingyang.github.io/codeagent/reference/shield_regex.md)
handles unregistered PII/secrets;
[`shield_ingress()`](https://kaipingyang.github.io/codeagent/reference/shield_ingress.md)
scans every tool’s arguments in the central permission gate and can
block or request approval before execution (built-in rules are
host-extensible: a `patterns=` name matching a built-in replaces it, a
new name adds to it).
[`shield_tool_policy()`](https://kaipingyang.github.io/codeagent/reference/shield_tool_policy.md)
provides exact/glob per-tool `scan`/`bypass`/`deny` rules; Shield bypass
is audited and never bypasses the separate permission gate.
[`shield_sandbox()`](https://kaipingyang.github.io/codeagent/reference/shield_sandbox.md)
preserves project/temp `rwx` and process execution by default, while
portable path policy blocks project-external and symlink-escaped paths;
`backend="auto"` currently reports/falls back to policy unless a full OS
adapter is available.
[`shield_reviewer()`](https://kaipingyang.github.io/codeagent/reference/shield_reviewer.md)
is an optional internal rail: a fresh, tool-less ellmer Chat reviews
only deterministically sanitized code/arguments; remote reviewers never
receive raw data/output, and missing/failed reviewers follow
configurable ask/block fail-closed policy. See the full [Data Shield
parameter
reference](https://kaipingyang.github.io/codeagent/articles/data-shield.html#current-parameter-reference).

Optional egress approval keeps raw disabled unless explicitly requested:

``` r

shield_egress(on_fail = "ask", allow_raw_approval = FALSE) # Redact / Block only
shield_egress(on_fail = "ask", allow_raw_approval = TRUE)  # adds RAW ONCE warning
```

No callback, timeout, error, or invalid choice defaults to redact.

The in-memory audit log records only non-sensitive decision metadata
(strategy, action, reason label, count, tool/id), never matched values
or raw results:

``` r

audit <- shield$audit(limit = 100)
shield$clear_audit()
```

Safe reference assets and protected datasets use separate type/access
axes:

``` r

shield$register_asset(
  adam_spec, name = "adam_spec", kind = "spec",
  llm_access = list(prompt = "raw", egress = "scan"),
  reason = "Validated public specification"
)
```

`kind` says what the asset is; `llm_access` says what may enter/leave
the LLM. Raw egress is never a default and requires provenance
(`shield$trusted_result()`), a reason, expiry/session scope, and audit.

### Skill system

Compatible with Claude Code and btw skill format (`name/SKILL.md`
directories).

``` r

# Install Posit's data-science skill collection
install_ds_skills()

# Install from a package or GitHub
btw::btw_skill_install_package("btw")
btw::btw_skill_install_github("org/repo")
```

Built-in slash commands: `/compact`, `/plan`, `/verify`, `/simplify`,
`/loop`, `/remember`

### Multi-agent teams

``` r

# Work-stealing over a shared SQLite board
team_coordinate(c("task 1", "task 2", "task 3"))

# LLM-lead coordinator: decomposes goal into DAG, runs team, re-plans
team_lead("Refactor the parser and add tests", max_rounds = 3)
```

### MCP server

``` r

codeagent_mcp_server()
# Claude Desktop config:
# {"mcpServers": {"codeagent": {"command": "Rscript",
#   "args": ["-e", "codeagent::codeagent_mcp_server()"]}}}
```

### Shiny app

``` r

# Single-user / interactive convenience:
codeagent_app(
  client,
  theme         = "default",   # "default" | "flatly" | "darkly" | "glass"
  pinned_skills = c("plan", "compact")
)

# Multi-user deployment: create mutable client/chat state per Shiny session.
codeagent_app(client_factory = function(session) {
  codeagent_client(ellmer::chat_openai_compatible(
    base_url = Sys.getenv("CODEAGENT_BASE_URL"),
    model = Sys.getenv("CODEAGENT_MODEL"),
    credentials = function() Sys.getenv("CODEAGENT_API_KEY")))
})
```

## Configuration reference

Precedence (low → high): package defaults → `~/.codeagent/settings.json`
→ `.codeagent/settings.json` → environment variables.

``` json
{
  "provider": "openai_compatible",
  "model": "main",
  "env": {
    "CODEAGENT_BASE_URL": "https://YOUR-WORKSPACE/serving-endpoints",
    "CODEAGENT_MODEL":       "your-main-endpoint",
    "CODEAGENT_HEAVY_MODEL": "your-heavy-endpoint",
    "CODEAGENT_FAST_MODEL":  "your-fast-endpoint"
  },
  "permissions": {
    "allow": [],
    "deny":  [],
    "ask":   [],
    "defaultMode": "default"
  },
  "effortLevel": "high",
  "hooks": {}
}
```

> **API key:** keep `CODEAGENT_API_KEY` in `~/.Renviron`, not in
> `settings.json`.

## Supported providers

| Provider                                       | `"provider"` value    |
|------------------------------------------------|-----------------------|
| OpenAI-compatible (Databricks, Azure, vLLM, …) | `"openai_compatible"` |
| Anthropic                                      | `"anthropic"`         |
| OpenAI                                         | `"openai"`            |
| Google Gemini                                  | `"google_gemini"`     |
| Ollama                                         | `"ollama"`            |
| Posit AI                                       | `"posit"`             |
| AWS Bedrock                                    | `"aws_bedrock"`       |
| Azure OpenAI                                   | `"azure_openai"`      |

## Related

- [ellmer](https://ellmer.tidyverse.org) — LLM client for R
- [btw](https://btw.posit.co) — R-environment tools for LLMs
- [shinychat](https://posit-dev.github.io/shinychat/) — Chat UI
  components

## License

MIT
