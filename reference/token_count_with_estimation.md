# Token count preferring real usage over the char heuristic

Mirrors Claude Code `tokenCountWithEstimation` (src/utils/tokens.ts):
use the real token usage from the last API exchange when available,
otherwise fall back to the char/3.5 estimate. This makes the compaction
trigger fire on actual model token counts rather than a rough character
approximation.

## Usage

``` r
token_count_with_estimation(chat, allow_network = FALSE)
```

## Arguments

- chat:

  An [`ellmer::Chat`](https://ellmer.tidyverse.org/reference/Chat.html)
  object.

- allow_network:

  Logical. If `TRUE`, explicitly call
  `chat$token_count(include = "complete")`; defaults to `FALSE` so UI
  and compaction paths never perform implicit token-count HTTP requests.

## Value

Integer token count.
