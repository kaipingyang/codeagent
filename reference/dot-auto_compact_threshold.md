# Auto-compaction threshold (= getAutoCompactThreshold, autoCompact.ts:72)

Auto-compaction threshold (= getAutoCompactThreshold, autoCompact.ts:72)

## Usage

``` r
.auto_compact_threshold(model, chat = NULL, context_window = NULL)
```

## Arguments

- model:

  Character. Model id/name.

- chat:

  An [`ellmer::Chat`](https://ellmer.tidyverse.org/reference/Chat.html)
  or NULL (used to read provider-reported window).

- context_window:

  Optional explicit raw context window. When supplied it is reduced by
  the same model output reserve and autocompact buffer.

## Value

Integer token count at/above which auto-compaction should trigger.
