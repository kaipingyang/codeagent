# codeagent

An R-native agentic coding assistant built on [ellmer](https://ellmer.tidyverse.org) and [btw](https://btw.posit.co). It reimplements a coding-agent **harness** in R: the agent loop, permission system, context compaction, hook system, skill system, tool execution, session management, multi-agent coordination, a CLI REPL, and an interactive Shiny UI.

> **Not a wrapper.** codeagent reimplements the harness from scratch rather than shelling out to an external CLI.

## Installation

```r
# Install from GitHub (requires ellmer dev version for set_model())
pak::pak(c("tidyverse/ellmer", "kaipingyang/codeagent"))

# Optional: btw for R-environment tools (docs, git, pkg, env, etc.)
pak::pak("posit-dev/btw")

# Optional: shinychat dev for latest chat UI
pak::pak("posit-dev/shinychat/pkg-r")
```

## Quick start

```r
library(codeagent)

# Step 1: create any ellmer Chat (Databricks, Anthropic, Ollama, ...)
chat <- ellmer::chat_openai_compatible(
  base_url    = Sys.getenv("CODEAGENT_BASE_URL"),
  model       = Sys.getenv("CODEAGENT_MODEL"),
  credentials = function() Sys.getenv("CODEAGENT_API_KEY")
)

# Step 2: wrap into a codeagent client (injects tools + system prompt)
client <- codeagent_client(chat, permission_mode = "bypass")

# Step 3a: one-shot query
codeagent(client, "List all .R files in R/")

# Step 3b: interactive Shiny app
codeagent_app(client, theme = "default")

# Step 3c: interactive CLI REPL
codeagent_repl(client)
```

### Interactive setup wizard

```r
use_codeagent_setup()   # guides provider selection + API key + settings.json
```

### From a config file

```yaml
# codeagent.md
---
client:
  gpt41:    openai/gsds-gpt41
  deepseek: openai/deepseek-r1
btw_groups: [docs, git, pkg]
permission_mode: bypass
---
Follow tidyverse style.
```

```r
client <- codeagent_client_config(alias = "gpt41")
codeagent_app(client)
```

## Features

### Agent harness

| Feature | Details |
|---------|---------|
| **Agent loop** | `agent_loop()` with max_turns, budget tracking, compaction |
| **Permissions** | 7 modes: `default`, `plan`, `accept_edits`, `bypass`, `dont_ask`, `auto`, `bubble`; fine-grained rules match tool arguments |
| **Hooks** | 12 lifecycle events (tool, permission, message, session), configurable from `settings.json` |
| **Compaction** | Dynamic per-model context window + two-level flow (session-memory summary → full 9-section summary), real token counts via `get_tokens()`, PTL/413 fallback, and an "N% context left" indicator (REPL + Shiny) |
| **System prompt** | Tone, task, convention, tool-use, and R-specific behavioural guidance |
| **Error recovery** | PTL/rate-limit/network/auth classification; exponential backoff |
| **system-reminder** | Ephemeral per-turn context injection preserves prompt cache |
| **Verification** | `verify_fn` param + `verify_r_tests()` re-enters loop on test failures |
| **Plan mode** | Model enters/exits read-only planning mid-turn |
| **Rewind** | `truncate_chat_turns()` / REPL `/rewind` roll the conversation back |
| **Model switch** | `switch_model(client, model)` swaps provider/model mid-session |

### Tools

| Group | Source | Tools |
|-------|--------|-------|
| Core | codeagent | Bash, Read, Write, Edit, MultiEdit, Glob, Grep, LS |
| docs | btw | help pages, vignettes, NEWS |
| env | btw | describe data frames / R environment |
| files | btw | hashline-based precise editing + atomic multi-file patch |
| git | btw | status, diff, log, commit, branches |
| ide | btw | read current editor |
| pkg | btw | document, check, test, coverage, load_all |
| cran | btw | search, package info |
| sessioninfo | btw | platform, package versions |
| web | btw | URL → Markdown |
| agent | btw | hierarchical subagent delegation |
| data | codeagent | `ExploreData` — sandboxed data.frame queries |

All tools return `ContentToolResult` with HTML title + markdown for shinychat tool cards.

### Data exploration (WEAR loop)

Interactive data analysis with the Write/Execute/Analyze/Regroup pattern:

```r
# Start a WEAR session -- agent writes code, executes via ExploreData,
# analyzes results, proposes 3-5 follow-up questions each turn
wear_explore(data = list(sales = my_df))

# Export the session to a reproducible Quarto document
generate_wear_report(client, path = "analysis.qmd", title = "Sales Analysis")
# Render: quarto render analysis.qmd
```

`ExploreData` runs in a sandboxed sub-environment (read-only, cannot modify source data).

### Skill system

Compatible with Claude Code and btw skill format (`name/SKILL.md` directories).

```
Discovery order:
  codeagent inst/skills/ → btw paths → ~/.codeagent/skills/
  → .codeagent/skills/ → .claude/skills/ → .codex/skills/
```

Two trigger paths:
- **User** types `/name [args]` → `load_skill_prompt()` injects full body
- **LLM semantic match** → calls `use_skill(name)` tool automatically

Built-in skills: `/compact`, `/plan`, `/verify`, `/simplify`, `/loop`, `/remember`,
`/explore`, `/report`

Install btw skills:
```r
btw::btw_skill_install_package("btw")     # installs skill-creator
btw::btw_skill_install_github("org/repo") # from GitHub
```

### Security: API key storage

```r
# Option 1: OS keyring (macOS Keychain / Windows Credential Store / Linux Secret Service)
# Offered automatically in setup wizard when keyring is available
use_codeagent_setup()

# Option 2: ~/.Renviron (plaintext, existing behaviour -- fallback when keyring unavailable)
```

`keyring` is optional (`Suggests`). On headless/server environments the keyring probe
returns `FALSE` and all functions fall back to `~/.Renviron` silently.

### Sub-agents

```r
# Sub-agent with isolated, resumable session
client <- codeagent_client(chat, permission_mode = "bypass")

# Run sub-agent in isolated git worktree
client <- codeagent_client(chat, worktree_isolation = TRUE)
```

### Multi-agent teams

```r
# Fixed fan-out: one worker per task
team_run(c("review R/a.R", "review R/b.R", "review R/c.R"))

# Work-stealing over shared SQLite board (balances uneven task sizes)
team_coordinate(c("task 1", "task 2", "task 3", "task 4"))
```

### Sandboxed R execution

`RunR` executes R code in a `callr` subprocess with a scrubbed environment (no API
keys visible) and wall-clock timeout:

```json
// ~/.codeagent/settings.json
{ "sandbox": { "enabled": true, "allow_network": false } }
```

### Eval harness (vitals)

```r
# Run all eval tasks (measures tool use, permissions, data exploration)
source("inst/evals/setup_eval_client.R")
source("inst/evals/eval.R")
vitals::vitals_view()
```

### Persistent memory

Facts the agent remembers across sessions are stored under `~/.codeagent/memory/`.
On the first turn, only memories relevant to the current request are recalled
(selected by a small fast model).

### IDE Addin

```r
# Run from RStudio / Positron Addins menu:
# "codeagent: Open chat" -- opens Shiny app for current file/project
# "codeagent: Chat about selection" -- sends selected text as context
```

### MCP server

```r
codeagent_mcp_server()
# Claude Desktop: {"mcpServers": {"codeagent": {"command": "Rscript",
#   "args": ["-e", "codeagent::codeagent_mcp_server()"]}}}
```

### CLI (requires Rapp)

```r
install_codeagent_cli()
```

```bash
codeagent run "List all .R files"
codeagent chat                      # interactive REPL
codeagent app --theme glass
codeagent skills list
codeagent skills install --package btw
codeagent mcp
codeagent info --json
```

### Shiny app

Four themes, three-panel accordion sidebar:

```r
codeagent_app(
  client,
  theme         = "default",   # "default" | "flatly" | "darkly" | "glass"
  pinned_skills = c("plan", "compact"),
  port          = NULL
)
```

**Sessions** panel: save/load/fork/rename conversations, rewind turns.
**Skills** panel: searchable, scrollable, one-click fill, + install button.
**Settings** panel: permission mode, btw tool group toggles, theme switch.

**Interactive pauses** (in-chat bar above the input):
- **Permission approval** — in `default` mode, risky tools (Write/Edit/MultiEdit/Bash/RunR)
  pause with an Allow/Deny bar before running; the agent loop resumes on your choice.
- **AskUserQuestion** — the model can pause to ask a clarifying question (radio choices or
  free text) and continues once you answer. ESC dismisses a pause without deadlocking the loop.

Both ride an async promise mechanism, so only the Shiny path is async; the CLI/one-shot path
stays synchronous (approvals use the console prompt).

## Configuration (settings.json)

```r
use_codeagent_settings(scope = "user")   # scaffold ~/.codeagent/settings.json
```

Precedence (low to high): package defaults < `~/.codeagent/settings.json` <
`.codeagent/settings.json` < environment variables.

> **Config directory.** User-global config/sessions live in the OS-standard
> location (`rappdirs::user_config_dir("codeagent")`; e.g. `~/.config/codeagent`
> on Linux). A legacy `~/.codeagent` is migrated automatically on first use
> (non-destructive copy), and still read as a fallback. Override with
> `CODEAGENT_HOME`, or migrate manually via `migrate_config_dir()`.

```json
{
  "provider": "openai_compatible",
  "model": "your-model",
  "env": {
    "CODEAGENT_BASE_URL": "https://YOUR-WORKSPACE/serving-endpoints",
    "CODEAGENT_SMALL_FAST_MODEL": "your-haiku-endpoint"
  },
  "permissions": { "allow": [], "deny": [], "ask": [], "defaultMode": "default" },
  "sandbox": { "enabled": false, "allow_network": true },
  "hooks": {},
  "effortLevel": "high"
}
```

The `env` block is applied before environment variables are read, so it works
even under `Rscript --vanilla`. **Never put API keys in `settings.json`** — keep
them in `.Renviron` as `CODEAGENT_API_KEY`, or use keyring (see above).

## Supported providers

| Provider | `settings.json` `"provider"` | Notes |
|----------|------|-------|
| OpenAI-compatible | `"openai_compatible"` | Databricks, Azure, vLLM, custom |
| Anthropic | `"anthropic"` | |
| OpenAI | `"openai"` | |
| Google Gemini | `"google_gemini"` | |
| DeepSeek | `"deepseek"` | reasoning_content → ContentThinking |
| Groq | `"groq"` | |
| GitHub Copilot | `"github"` | |
| Ollama | `"ollama"` | local |
| Posit AI | `"posit"` | OAuth device flow |
| Databricks | `"databricks"` | |
| AWS Bedrock | `"aws_bedrock"` | |
| Azure OpenAI | `"azure_openai"` | |

## Architecture

```
┌─────────────────────────────────────────────┐
│  codeagent_client(chat)  ← CodagentClient   │
│    ├─ tools: 8 built-in + btw 10 groups     │
│    ├─ ExploreData (optional WEAR mode)       │
│    ├─ skill tool (use_skill)                 │
│    └─ system prompt (skills + CLAUDE.md)     │
└────────────────┬────────────────────────────┘
                 │
         agent_loop() / codeagent_app()
                 │
    ┌────────────▼────────────────────────────┐
    │            HARNESS                      │
    │  system-reminder → compaction →         │
    │  ellmer Chat → hooks → verify           │
    └─────────────────────────────────────────┘
```

## Related

- [ellmer](https://ellmer.tidyverse.org) — LLM client for R
- [btw](https://btw.posit.co) — R-environment tools for LLMs
- [shinychat](https://posit-dev.github.io/shinychat/) — Chat UI components
- [vitals](https://vitals.tidymodels.org) — LLM eval framework

## License

MIT
