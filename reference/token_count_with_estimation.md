# Token count preferring real usage over the char heuristic

Mirrors Claude Code `tokenCountWithEstimation` (src/utils/tokens.ts):
use the real token usage from the last API exchange when available,
otherwise fall back to the char/3.5 estimate. This makes the compaction
trigger fire on actual model token counts rather than a rough character
approximation.

## Usage

``` r
token_count_with_estimation(chat)
```

## Arguments

  - chat:
    
    An `ellmer::Chat` object.

## Value

Integer token count.
