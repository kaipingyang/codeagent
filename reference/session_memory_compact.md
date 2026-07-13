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
  max_tokens = .COMPACT_L2_MAX_TOKENS
)
```

## Arguments

  - chat:
    
    An `ellmer::Chat` object.

  - model:
    
    Character. Haiku model for summarisation.

  - min\_messages:
    
    Integer. Minimum number of text messages to keep.

  - min\_tokens:
    
    Integer. Minimum tokens to retain.

  - max\_tokens:
    
    Integer. Maximum tokens for the summary section.

## Value

Invisibly NULL.
