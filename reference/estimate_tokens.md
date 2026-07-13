# Estimate token count for an ellmer Chat object

Uses the char/4 heuristic across all turns.

## Usage

``` r
estimate_tokens(chat)
```

## Arguments

- chat:

  An [`ellmer::Chat`](https://ellmer.tidyverse.org/reference/Chat.html)
  object.

## Value

Integer. Estimated token count.
