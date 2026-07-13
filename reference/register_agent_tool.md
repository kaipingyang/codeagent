# Register the Agent tool and any btw custom agent tools

Registers `btw_tool_agent_subagent` (or fallback), plus any custom
agents discovered from `.btw/agent-*.md`, `.claude/agents/`, etc.

## Usage

``` r
register_agent_tool(
  chat,
  model = "claude-sonnet-4-6",
  mode = "default",
  rules = list(),
  max_turns = 30L,
  worktree_isolation = FALSE,
  ask_fn = NULL
)
```

## Arguments

- chat:

  An [`ellmer::Chat`](https://ellmer.tidyverse.org/reference/Chat.html)
  object.

- model:

  Character. Model for sub-agents (fallback).

- mode:

  Character. Permission mode.

- rules:

  List. Permission rules.

- max_turns:

  Integer. Max turns per sub-agent.

- worktree_isolation:

  Logical. Run sub-agents in isolated git worktrees.

- ask_fn:

  Function or NULL. Parent permission callback forwarded to the
  sub-agent (which runs in "bubble" mode).

## Value

Invisibly returns `chat`.
