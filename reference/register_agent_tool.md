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
  ask_fn = NULL,
  async = FALSE,
  data_shield = NULL,
  cwd = getwd(),
  parent_chat = NULL,
  hooks = NULL
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

- async:

  Logical. Passed to
  [`agent_tool()`](https://kaipingyang.github.io/codeagent/reference/agent_tool.md);
  enables concurrent sub-agents on async parent turns. Default `FALSE`.

- data_shield:

  Optional
  [DataShield](https://kaipingyang.github.io/codeagent/reference/DataShield.md)
  inherited by codeagent sub-agents; disables uninstrumented
  btw/custom-agent delegation.

- cwd:

  Character. Working directory used for upstream agent discovery.

- parent_chat:

  Optional parent
  [`ellmer::Chat`](https://ellmer.tidyverse.org/reference/Chat.html);
  reserved for owned sub-agent lifecycle integration.

- hooks:

  Optional
  [HookRegistry](https://kaipingyang.github.io/codeagent/reference/HookRegistry.md)
  used for SubagentStart/Stop lifecycle events on the owned codeagent
  Agent path.

## Value

Invisibly returns `chat`.
