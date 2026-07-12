# Auto-compaction threshold (= getAutoCompactThreshold, autoCompact.ts:72)

Auto-compaction threshold (= getAutoCompactThreshold, autoCompact.ts:72)

## Usage

``` r
.auto_compact_threshold(model, chat = NULL)
```

## Arguments

- model:

  Character. Model id/name.

- chat:

  An [`ellmer::Chat`](https://ellmer.tidyverse.org/reference/Chat.html)
  or NULL (used to read provider-reported window).

## Value

Integer token count at/above which auto-compaction should trigger.
