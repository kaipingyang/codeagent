# Initialise a project-context file (btw.md) via btw's guided task (reuse)

Initialise a project-context file (btw.md) via btw's guided task (reuse)

## Usage

``` r
codeagent_init_context(client = NULL, mode = "console", ...)
```

## Arguments

- client:

  A codeagent client or an
  [`ellmer::Chat`](https://ellmer.tidyverse.org/reference/Chat.html)
  (its chat is reused).

- mode:

  One of `"console"`, `"app"`, `"client"`, `"tool"`.

- ...:

  Passed to
  [`btw::btw_task_create_btw_md()`](https://posit-dev.github.io/btw/reference/btw_task_create_btw_md.html).

## Value

See
[`btw::btw_task_create_btw_md()`](https://posit-dev.github.io/btw/reference/btw_task_create_btw_md.html).
