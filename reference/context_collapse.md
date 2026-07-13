# L5: Context collapse via read-time projection

Replaces the `value` field of all `ContentToolResult` objects in the
conversation with a short summary, collapsing large tool outputs without
dropping turns. Unlike L1 (which uses a fixed placeholder), this uses
the first `max_chars` characters plus a token estimate notice.

## Usage

``` r
context_collapse(chat, max_chars = 200L)
```

## Arguments

- chat:

  An [`ellmer::Chat`](https://ellmer.tidyverse.org/reference/Chat.html)
  object.

- max_chars:

  Integer. Max characters to retain per tool result.

## Value

Invisibly NULL.

## Details

Called when token count is critically high and L3 full compaction has
already been attempted (or failed). This is the lightest non-destructive
option before L4 drop.
