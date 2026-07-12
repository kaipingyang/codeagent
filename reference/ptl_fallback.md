# L4: Prompt-too-long fallback – drop oldest turns

Called when the API returns a 413 / prompt_too_long error. When the
error message carries a real context limit (Claude Code parses
`contextLimit`), drop the oldest turns until the estimate is under ~90%
of that limit; otherwise drop a fixed number of oldest turns.

## Usage

``` r
ptl_fallback(chat, drop_turns = 3L, error_msg = NULL)
```

## Arguments

- chat:

  An [`ellmer::Chat`](https://ellmer.tidyverse.org/reference/Chat.html)
  object.

- drop_turns:

  Integer. Turns to drop when no limit can be parsed.

- error_msg:

  Character or NULL. The PTL/413 error message to parse.

## Value

Invisibly NULL.
