# Context-budget warning state (= calculateTokenWarningState, autoCompact.ts)

Computes how much context is left and which thresholds have been
crossed, for the "X% context left" indicator in the REPL banner and
Shiny status bar.

## Usage

``` r
calculate_token_warning_state(token_usage, model, chat = NULL)
```

## Arguments

  - token\_usage:
    
    Integer. Current token usage (see
    [token\_count\_with\_estimation](https://kaipingyang.github.io/codeagent/reference/token_count_with_estimation.md)).

  - model:
    
    Character. Model id/name.

  - chat:
    
    An `ellmer::Chat` or NULL.

## Value

A list: `percent_left`, `above_warning`, `above_error`, `above_compact`,
`at_blocking`.
