# L2: Incremental session memory compaction

Summarises early turns while retaining recent context. Keeps between
`min_tokens` and `max_tokens` in the summary.

## Usage

``` r
session_memory_compact(
  chat,
  model = .HAIKU_MODEL,
  min_messages = 5L,
  min_tokens = .COMPACT_L2_MIN_TOKENS,
  max_tokens = .COMPACT_L2_MAX_TOKENS,
  pending_turn = NULL
)
```

## Arguments

- chat:

  An [`ellmer::Chat`](https://ellmer.tidyverse.org/reference/Chat.html)
  object.

- model:

  Character. Haiku model for summarisation.

- min_messages:

  Integer. Minimum number of text messages to keep.

- min_tokens:

  Integer. Minimum tokens to retain.

- max_tokens:

  Integer. Maximum tokens for the summary section.

- pending_turn:

  Optional outgoing pending turn used for pairing validation.

## Value

Invisibly TRUE after a validated history write, otherwise NULL.
