# Create the TaskUpdate tool

Create the TaskUpdate tool

## Usage

``` r
task_update_tool(store, hooks = NULL)
```

## Arguments

- store:

  Environment. Per-session task store from `.new_task_store()`.

- hooks:

  A
  [HookRegistry](https://kaipingyang.github.io/codeagent/reference/HookRegistry.md)
  or NULL. Fires `TaskCompleted` on the pending/in_progress -\>
  completed transition (once, not on repeat updates).

## Value

An [`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html)
object.
