# Create a skill via btw's guided task (reuse)

Create a skill via btw's guided task (reuse)

## Usage

``` r
codeagent_create_skill(client = NULL, mode = "console", ...)
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
  [`btw::btw_task_create_skill()`](https://posit-dev.github.io/btw/reference/btw_task_create_skill.html).

## Value

See
[`btw::btw_task_create_skill()`](https://posit-dev.github.io/btw/reference/btw_task_create_skill.html).
