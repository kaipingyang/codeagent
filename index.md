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

# Optional: btw for R-environment tools (docs, git, pkg, env, etc.)
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

| Feature            | Details                                                                                                                                                                                                                                                     |
| ------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Agent loop**     | `agent_loop()` with max\_turns, budget tracking, compaction                                                                                                                                                                                                 |
| **Permissions**    | 7 modes: `default`, `plan`, `accept_edits`, `bypass`, `dont_ask`, `auto`, `bubble`; fine-grained rules match tool arguments                                                                                                                                 |
| **Hooks**          | 12 lifecycle events (tool, permission, message, session), configurable from `settings.json`                                                                                                                                                                 |
| **Compaction**     | Dynamic per-model context window + two-level flow (session-memory summary → full 9-section summary), real token counts via `get_tokens()`, PTL/413 fallback, an “N% context left” indicator (REPL + Shiny), and **mid-loop compaction** between tool rounds |
| **System prompt**  | Tone, task, convention, tool-use, and R-specific behavioural guidance                                                                                                                                                                                       |
| **Error recovery** | PTL/rate-limit/network/auth classification; exponential backoff                                                                                                                                                                                             |
| **Verification**   | `verify_fn` param + `verify_r_tests()` re-enters loop on test failures                                                                                                                                                                                      |
| **Plan mode**      | Model enters/exits read-only planning mid-turn                                                                                                                                                                                                              |
| **Rewind**         | `truncate_chat_turns()` / REPL `/rewind` roll the conversation back                                                                                                                                                                                         |
| **Model switch**   | `switch_model(client, model)` swaps provider/model mid-session                                                                                                                                                                                              |

### Tools

| Group | Source    | Tools                                                   |
| ----- | --------- | ------------------------------------------------------- |
| Core  | codeagent | Bash, Read, Write, Edit, MultiEdit, Glob, Grep, LS      |
| docs  | btw       | help pages, vignettes, NEWS                             |
| env   | btw       | describe data frames / R environment                    |
| files | btw       | hash-anchored precise editing + atomic multi-file patch |
| git   | btw       | status, diff, log, commit, branches                     |
| pkg   | btw       | document, check, test, coverage, load\_all              |
| web   | btw       | URL → Markdown                                          |
| agent | btw       | hierarchical subagent delegation                        |
| data  | codeagent | `ExploreData` — sandboxed data.frame queries            |

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
codeagent_app(
  client,
  theme         = "default",   # "default" | "flatly" | "darkly" | "glass"
  pinned_skills = c("plan", "compact")
)
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
| ---------------------------------------------- | --------------------- |
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
