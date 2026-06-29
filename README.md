# codeagent

An R-native agentic coding assistant built on [ellmer](https://ellmer.tidyverse.org) + [btw](https://btw.posit.co). Implements the full Claude Code **harness** layer in R: agent loop, permissions, compaction, skill system, tool execution, session management, and an interactive Shiny UI.

> **Not a wrapper.** codeagent reimplements the harness from scratch — the same architecture described in [arXiv 2604.14228](https://arxiv.org/abs/2604.14228).

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

# Step 1: create any ellmer Chat (Databricks, Anthropic, Ollama, …)
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
| **Permissions** | 7 modes: `default`, `plan`, `accept_edits`, `bypass`, `dont_ask`, `auto`, `bubble` |
| **Hooks** | 7 lifecycle events: `PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `PermissionDenied`, `PermissionRequest`, `UserMessage`, `AssistantMessage` |
| **Compaction** | 5 levels: snip → memory summary → full compact → PTL fallback → context collapse |
| **Error recovery** | Classifies PTL/rate-limit/network/auth; exponential backoff for rate limits |
| **system-reminder** | Ephemeral per-turn context injection (date, iteration, cwd) — preserves prompt cache |
| **Verification** | `verify_fn` param + `verify_r_tests()` re-enters loop on test failures |

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
| web | btw | URL → Markdown |
| agent | btw | hierarchical subagent delegation |

All tools return `ContentToolResult` with HTML title + markdown for shinychat tool cards.

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

Built-in skills: `/compact`, `/plan`, `/verify`, `/simplify`, `/loop`, `/remember`

Install btw skills:
```r
btw::btw_skill_install_package("btw")     # installs skill-creator
btw::btw_skill_install_github("org/repo") # from GitHub
```

### Sub-agents

```r
# btw_tool_agent_subagent (isolated chat session, resumable)
client <- codeagent_client(chat, permission_mode = "bypass")

# Optional: run sub-agent in isolated git worktree
client <- codeagent_client(chat, worktree_isolation = TRUE)
```

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
│  codeagent_client(chat)  ← CodagentClient   │
│    ├─ tools: 8 built-in + btw 10 groups      │
│    ├─ skill tool (use_skill)                 │
│    └─ system prompt (skills + CLAUDE.md)     │
└────────────────┬────────────────────────────┘
                 │
         agent_loop() / codeagent_app()
                 │
    ┌────────────▼────────────────────────────┐
    │         HARNESS                         │
    │  system-reminder → compaction →         │
    │  ellmer Chat → hooks → verify           │
    └─────────────────────────────────────────┘
```

## Related

- [ellmer](https://ellmer.tidyverse.org) — LLM client for R
- [btw](https://btw.posit.co) — R-environment tools for LLMs
- [shinychat](https://posit-dev.github.io/shinychat/) — Chat UI components

## License

MIT
