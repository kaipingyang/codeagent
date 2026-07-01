# codeagent

An R-native agentic coding assistant built on [ellmer](https://ellmer.tidyverse.org) and [btw](https://btw.posit.co). It reimplements a coding-agent **harness** in R: the agent loop, permission system, context compaction, hook system, skill system, tool execution, session management, multi-agent coordination, a CLI REPL, and an interactive Shiny UI.

> **Not a wrapper.** codeagent reimplements the harness from scratch rather than shelling out to an external CLI.

## Installation

```r
# Install from GitHub
pak::pak("kaipingyang/codeagent")

# btw for R-environment tools (docs, git, pkg, env, etc.)
pak::pak("posit-dev/btw")
```

## Quick start

```r
library(codeagent)

# Step 1: create any ellmer Chat (Databricks, Anthropic, Ollama, ...)
chat <- ellmer::chat_openai_compatible(
  base_url    = Sys.getenv("CODEAGENT_BASE_URL"),   # e.g. Databricks serving-endpoints
  model       = Sys.getenv("CODEAGENT_MODEL"),
  credentials = function() Sys.getenv("CODEAGENT_API_KEY")
)

# Step 2: wrap into a codeagent client (injects tools + system prompt)
client <- codeagent_client(chat, permission_mode = "bypass")

# Step 3a: one-shot query
codeagent(client, "List all .R files in R/")

# Step 3b: interactive Shiny app
codeagent_app(client, theme = "default")
```

## Thinking / reasoning support

`codeagent` can use any `ellmer` chat backend, but visible thinking depends on the
provider response format.

- `deepseek-r1` via `chat_openai_compatible()` works out of the box; ellmer maps
  `reasoning_content` to `ContentThinking`.
- GPT-style `reasoning_effort` can be sent to compatible endpoints, but this does
  not expose raw thinking text; you typically only see usage metadata.
- Databricks-hosted Claude extended thinking is not parsed by ellmer's current
  `ProviderOpenAICompatible` implementation because it returns typed content blocks
  instead of `reasoning_content`.

Reference scripts:

- `inst/examples/demo_04_thinking.R`: supported end-to-end example using `deepseek-r1`
- `references/thinking_claude_haiku.R`: runtime monkey-patch for Databricks Claude
- `references/thinking_claude_httr2.R`: raw `httr2` request that prints reasoning blocks
- `references/ellmer_chat.R`: side-by-side notes for basic chat, GPT reasoning, and thinking

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
| **Permissions** | 7 modes: `default`, `plan`, `accept_edits`, `bypass`, `dont_ask`, `auto`, `bubble`; fine-grained rules match tool arguments, e.g. `Bash(npm run test *)` |
| **Hooks** | 12 lifecycle events (tool, permission, message, and session events), configurable declaratively from `settings.json` |
| **Compaction** | 5 levels: snip -> memory summary -> full compact -> PTL fallback -> context collapse |
| **System prompt** | Tone, task, convention, tool-use, and R-specific behavioural guidance |
| **Error recovery** | Classifies PTL/rate-limit/network/auth; exponential backoff for rate limits |
| **system-reminder** | Ephemeral per-turn context injection (date, iteration, cwd) preserves prompt cache |
| **Verification** | `verify_fn` param + `verify_r_tests()` re-enters loop on test failures |
| **Plan mode** | The model can enter/exit read-only planning mid-turn via plan-mode tools |
| **Rewind** | `truncate_chat_turns()` / REPL `/rewind` roll the conversation back |

### Tools

| Group | Source | Tools |
|-------|--------|-------|
| Core | codeagent | Bash, Read, Write, Edit, MultiEdit, Glob, Grep, LS |
| docs | btw | help pages, vignettes, NEWS |
| env | btw | describe data frames / R environment |
| files | btw | hashline-based precise editing |
| git | btw | status, diff, log, commit, branches |
| ide | btw | read current editor |
| pkg | btw | document, check, test, coverage, load_all |
| cran | btw | search, package info |
| sessioninfo | btw | platform, package versions |
| web | btw | URL -> Markdown |
| agent | btw | hierarchical subagent delegation |

All tools return `ContentToolResult` with HTML title + markdown for shinychat tool cards.

### Skill system

Compatible with Claude Code and btw skill format (`name/SKILL.md` directories).

```
Discovery order:
  codeagent inst/skills/ -> btw paths -> ~/.codeagent/skills/
  -> .codeagent/skills/ -> .claude/skills/ -> .codex/skills/
```

Two trigger paths:
- **User** types `/name [args]` -> `load_skill_prompt()` injects full body
- **LLM semantic match** -> calls `use_skill(name)` tool automatically

Built-in skills: `/compact`, `/plan`, `/verify`, `/simplify`, `/loop`, `/remember`

Install btw skills:
```r
btw::btw_skill_install_package("btw")     # installs skill-creator
btw::btw_skill_install_github("org/repo") # from GitHub
```

### Sub-agents

```r
# Sub-agent with an isolated, resumable session (persisted as a sidechain)
client <- codeagent_client(chat, permission_mode = "bypass")

# Optional: run sub-agent in isolated git worktree
client <- codeagent_client(chat, worktree_isolation = TRUE)
```

### Multi-agent teams

Run independent tasks in parallel across `mirai` daemons, capped to the
container's CPU quota via `parallelly`:

```r
# Fixed fan-out: one worker per task
team_run(c("review R/a.R", "review R/b.R", "review R/c.R"))

# Work-stealing over a shared SQLite board (balances uneven task sizes,
# supports inter-agent messages)
team_coordinate(c("task 1", "task 2", "task 3", "task 4"))
```

The model can also call the `TeamRun` and `TeamCoordinate` tools directly.

### Sandboxed R execution

`RunR` executes R code behind the permission gate. Enable sandboxing to run it
in an isolated `callr` subprocess with a scrubbed environment (API keys are not
visible to the executed code), no `.Renviron` reload, and a wall-clock timeout:

```r
client <- codeagent_client(
  chat,
  permission_mode = "bypass"
)
# Enable via settings.json:  "sandbox": { "enabled": true, "allow_network": false }
```

Sandboxing is opt-in: it isolates each call in a fresh process (a small spawn
cost), so it is off by default for local, trusted use and recommended when
running less-trusted code.

### Persistent memory

Facts the agent should remember across sessions are stored under
`~/.codeagent/memory/`. On the first turn of a session, only the memories
relevant to the current request are recalled (selected by a small fast model),
rather than concatenating everything.

### MCP server

```r
# Expose all btw tools as an MCP server
codeagent_mcp_server()

# Claude Desktop config:
# {"mcpServers": {"codeagent": {"command": "Rscript",
#   "args": ["-e", "codeagent::codeagent_mcp_server()"]}}}
```

### CLI (requires Rapp)

```r
install_codeagent_cli()
```

```bash
codeagent run "List all .R files"
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
  theme         = "default",        # "default" | "flatly" | "darkly" | "glass"
  pinned_skills = c("plan", "compact"),
  port          = NULL
)
```

**Sessions** panel: save/load/fork conversations.
**Skills** panel: searchable, scrollable, one-click fill, + install button.
**Settings** panel: permission mode, btw tool group toggles, theme switch.

## Configuration (settings.json)

Scaffold a settings file (user or project scope):

```r
use_codeagent_settings(scope = "user")   # ~/.codeagent/settings.json
```

It mirrors the schema of command-line coding agents. Precedence (low to high):
package defaults < `~/.codeagent/settings.json` < `.codeagent/settings.json` <
environment variables. Highlights:

```json
{
  "model": "sonnet",
  "env": {
    "CODEAGENT_BASE_URL": "https://YOUR-WORKSPACE/serving-endpoints",
    "CODEAGENT_DEFAULT_SONNET_MODEL": "your-sonnet-endpoint",
    "CODEAGENT_SMALL_FAST_MODEL": "your-haiku-endpoint"
  },
  "permissions": { "allow": [], "deny": [], "ask": [], "defaultMode": "default" },
  "sandbox": { "enabled": false, "allow_network": true },
  "hooks": {},
  "effortLevel": "high"
}
```

The `env` block is applied before environment variables are read, so it works
even under `Rscript --vanilla`. Never put API keys in `settings.json` -- keep
them in `.Renviron` as `CODEAGENT_API_KEY`.

## Environment variables

| Variable | Purpose |
|----------|---------|
| `CODEAGENT_BASE_URL` | Serving endpoint URL (e.g. Databricks) |
| `CODEAGENT_MODEL` | Default model name |
| `CODEAGENT_API_KEY` | API key / token |
| `CODEAGENT_PERMISSION_MODE` | Override permission mode |
| `CODEAGENT_MAX_TURNS` | Override max turns |

## API reference

```r
# Factory
codeagent_client(chat, permission_mode, btw_groups, worktree_isolation, verify_fn, ...)
codeagent_client_config(alias, cwd)  # from codeagent.md

# Execution
codeagent(client, prompt)            # one-shot
agent_loop(user_input, client, ...)  # per-turn

# App
codeagent_app(client, theme, pinned_skills, port, launch.browser)

# Skills
list_skills_meta(cwd)
load_skill_prompt(name, args, cwd)
build_skill_hint(cwd, max_tokens)

# Sessions
list_sessions(cwd, limit)
save_session(chat, cwd, session_id)
get_session_messages(session_id, cwd)

# MCP / CLI
codeagent_mcp_server(tools)
install_codeagent_cli(destdir)
use_codeagent_md(path)

# Verification
verify_r_tests()   # returns a verify_fn for codeagent_client()

# Hooks
HookRegistry$new()
HookRegistry$register(HookEvent$USER_MESSAGE, fn)
HookEvent$PRE_TOOL_USE / POST_TOOL_USE / POST_TOOL_USE_FAILURE /
         PERMISSION_DENIED / PERMISSION_REQUEST /
         USER_MESSAGE / ASSISTANT_MESSAGE
```

## Architecture

```
┌─────────────────────────────────────────────┐
│  codeagent_client(chat)  <- CodagentClient   │
│    ├─ tools: 8 built-in + btw 10 groups      │
│    ├─ skill tool (use_skill)                 │
│    └─ system prompt (skills + CLAUDE.md)     │
└────────────────┬────────────────────────────┘
                 │
         agent_loop() / codeagent_app()
                 │
    ┌────────────▼────────────────────────────┐
    │         HARNESS                         │
    │  system-reminder -> compaction ->         │
    │  ellmer Chat -> hooks -> verify           │
    └─────────────────────────────────────────┘
```

## Related

- [ellmer](https://ellmer.tidyverse.org) -- LLM client for R
- [btw](https://btw.posit.co) -- R-environment tools for LLMs
- [shinychat](https://posit-dev.github.io/shinychat/) -- Chat UI components

## License

MIT
