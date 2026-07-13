# L1: Replace old tool results with a placeholder

Keeps the `keep_recent_turns` most recent turns intact and replaces
large tool results in earlier turns with a short placeholder.

## Usage

``` r
snip_old_tools(
  chat,
  keep_recent_turns = 10L,
  min_chars = 500L,
  target_tokens = NULL
)
```

## Arguments

- chat:

  An [`ellmer::Chat`](https://ellmer.tidyverse.org/reference/Chat.html)
  object (modified in place via set_turns).

- keep_recent_turns:

  Integer. Number of recent turns to leave untouched.

- min_chars:

  Integer. Only replace results larger than this size.

## Value

Invisibly NULL.
