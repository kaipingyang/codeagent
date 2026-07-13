# Run a btw task with a codeagent client (reuse, not reinvent)

Thin wrapper over `btw::btw_task()` so codeagent users can run any
markdown-defined btw task with their existing client's chat.

## Usage

``` r
codeagent_task(path, client = NULL, mode = "console", ...)
```

## Arguments

  - path:
    
    Path to a task markdown file (see `btw::btw_task()`).

  - client:
    
    A codeagent client or an `ellmer::Chat` (its chat is reused).

  - mode:
    
    One of `"console"`, `"app"`, `"client"`, `"tool"`.

  - ...:
    
    Passed to `btw::btw_task()`.

## Value

Whatever `btw::btw_task()` returns for the chosen mode.
