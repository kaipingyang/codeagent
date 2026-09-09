# Register per-request mid-loop compaction on a Chat

Adds an `on_request_start` callback that checks context before every
model request, including every tool-loop round. Default = budget-aware
micro snip (cheap, no LLM); opt in to a full two-level compact mid-loop
with `settings$midloop_full_compact`. The whole feature is gated by
`settings$midloop_compact` / `options(codeagent.midloop_compact = TRUE)`
(on by default via settings).

## Usage

``` r
register_midloop_compaction(chat, settings = list())
```

## Arguments

- chat:

  An [`ellmer::Chat`](https://ellmer.tidyverse.org/reference/Chat.html)
  object.

- settings:

  Named list from
  [`load_settings()`](https://kaipingyang.github.io/codeagent/reference/load_settings.md).

## Value

Invisibly `chat`.
