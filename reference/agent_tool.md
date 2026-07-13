# Create the Agent tool

When btw is available, delegates to `btw_tool_agent_subagent()` which
provides isolated chat sessions with resumable state. Falls back to
codeagent's own sub-agent loop otherwise.

## Usage

``` r
agent_tool(
  model = "claude-sonnet-4-6",
  mode = "default",
  rules = list(),
  max_turns = 30L,
  worktree_isolation = FALSE,
  hooks = NULL,
  ask_fn = NULL
)
```

## Arguments

- model:

  Character. Model for sub-agents (fallback only).

- mode:

  Character. Permission mode (inherited from parent).

- rules:

  List. Permission rules (inherited).

- max_turns:

  Integer. Max turns for sub-agent fallback (default 30).

- worktree_isolation:

  Logical. Run sub-agent in an isolated git worktree.

- hooks:

  A
  [HookRegistry](https://kaipingyang.github.io/codeagent/reference/HookRegistry.md)
  or NULL. Fires SubagentStart/Stop on the codeagent fallback sub-agent.
  Only applies to the fallback implementation; btw subagent handles its
  own isolation.

- ask_fn:

  Function or NULL. Parent permission callback. Sub-agents run in
  "bubble" mode, so any "ask" decision is forwarded to this function.

## Value

An [`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html)
object.
