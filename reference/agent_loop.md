# Main agentic query loop

Handles a single user turn. Accepts either a `CodeagentClient` (new
style) or the legacy `(chat, settings)` pair.

## Usage

``` r
agent_loop(
  user_input,
  client,
  settings = NULL,
  compaction_ctrl = CompactionController$new(),
  budget_tracker = BudgetTracker$new(),
  resource_state = ContentReplacementState$new(),
  hooks = NULL,
  cwd = NULL,
  session_id = NULL,
  iteration = 1L
)
```

## Arguments

- user_input:

  Character. User message.

- client:

  A `CodeagentClient` (from
  [`codeagent_client()`](https://kaipingyang.github.io/codeagent/reference/codeagent_client.md)),
  or an
  [`ellmer::Chat`](https://ellmer.tidyverse.org/reference/Chat.html) for
  legacy use.

- settings:

  Named list. Only needed in legacy mode (ignored when `client` is a
  `CodeagentClient`).

- compaction_ctrl:

  A
  [CompactionController](https://kaipingyang.github.io/codeagent/reference/CompactionController.md)
  R6 object.

- budget_tracker:

  A
  [BudgetTracker](https://kaipingyang.github.io/codeagent/reference/BudgetTracker.md)
  R6 object.

- resource_state:

  A
  [ContentReplacementState](https://kaipingyang.github.io/codeagent/reference/ContentReplacementState.md)
  R6 object.

- hooks:

  A
  [HookRegistry](https://kaipingyang.github.io/codeagent/reference/HookRegistry.md)
  R6 object or NULL.

- cwd:

  Character. Working directory (for session save). Overrides
  `client$settings$cwd` when provided explicitly.

- session_id:

  Character or NULL.

- iteration:

  Integer. Current loop iteration.

## Value

Named list: `response`, `session_id`, `stop_reason`.
