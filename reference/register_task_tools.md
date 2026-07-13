# Register task management tools to an ellmer Chat object

Creates a fresh per-session task store and registers TaskCreate,
TaskGet, TaskUpdate, TaskList tools. Each call gets an isolated store so
parallel agents do not collide on task IDs.

## Usage

``` r
register_task_tools(chat)
```

## Arguments

  - chat:
    
    An `ellmer::Chat` object.

## Value

Invisibly returns `chat`.
