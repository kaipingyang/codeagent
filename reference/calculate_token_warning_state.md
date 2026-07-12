# Context-budget warning state (= calculateTokenWarningState, autoCompact.ts)

Computes how much context is left and which thresholds have been
crossed, for the "X% context left" indicator in the REPL banner and
Shiny status bar.

## Usage

``` r
calculate_token_warning_state(token_usage, model, chat = NULL)
```

## Arguments

- token_usage:

  Integer. Current token usage (see
  [token_count_with_estimation](https://github.com/kaipingyang/codeagent/reference/token_count_with_estimation.md)).

- model:

  Character. Model id/name.

- chat:

  An [`ellmer::Chat`](https://ellmer.tidyverse.org/reference/Chat.html)
  or NULL.

## Value

A list: `percent_left`, `above_warning`, `above_error`, `above_compact`,
`at_blocking`.
