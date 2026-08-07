# Register task management tools to an ellmer Chat object

Creates a fresh per-session task store and registers TaskCreate,
TaskGet, TaskUpdate, TaskList tools. Each call gets an isolated store so
parallel agents do not collide on task IDs.

## Usage

``` r
register_task_tools(chat, hooks = NULL)
```

## Arguments

- chat:

  An [`ellmer::Chat`](https://ellmer.tidyverse.org/reference/Chat.html)
  object.

- hooks:

  A
  [HookRegistry](https://kaipingyang.github.io/codeagent/reference/HookRegistry.md)
  or NULL, forwarded to the task tools so they fire `TaskCreated` /
  `TaskCompleted`.

## Value

Invisibly returns `chat`.
