# L3: Full context compaction via fork agent

Spawns a separate haiku chat to generate a 9-section structured summary
wrapped in `<summary>` tags, then replaces all turns with that summary.

## Usage

``` r
full_compact(
  chat,
  model = .HAIKU_MODEL,
  instructions = NULL,
  pending_turn = NULL
)
```

## Arguments

- chat:

  An [`ellmer::Chat`](https://ellmer.tidyverse.org/reference/Chat.html)
  object.

- model:

  Character. Haiku model for compaction.

- instructions:

  Character or NULL. Optional user instructions to bias the summary.

- pending_turn:

  Optional outgoing pending turn used for pairing validation.

## Value

Invisibly TRUE after a validated history write, otherwise NULL.
