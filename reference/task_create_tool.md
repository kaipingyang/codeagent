# Create the TaskCreate tool

Create the TaskCreate tool

## Usage

``` r
task_create_tool(store, hooks = NULL)
```

## Arguments

- store:

  Environment. Per-session task store from `.new_task_store()`.

- hooks:

  A
  [HookRegistry](https://kaipingyang.github.io/codeagent/reference/HookRegistry.md)
  or NULL. Fires `TaskCreated` on create.

## Value

An [`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html)
object.
