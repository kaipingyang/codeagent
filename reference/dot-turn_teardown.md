# Run per-turn teardown: save session and return usage + cost.

Run per-turn teardown: save session and return usage + cost.

## Usage

``` r
.turn_teardown(client, cwd = NULL, session_id = NULL, presentation_text = NULL)
```

## Arguments

- client:

  A `CodeagentClient` or bare
  [`ellmer::Chat`](https://ellmer.tidyverse.org/reference/Chat.html).

- cwd:

  Character or NULL.

- session_id:

  Character or NULL.

- presentation_text:

  Character or NULL. Safe finalized assistant text for the session's
  presentation record.

## Value

Named list with elements:

- `n_tokens`: integer token count (real or estimated)

- `model_limit`: integer context window limit

- `warning_state`: list from
  [`calculate_token_warning_state()`](https://kaipingyang.github.io/codeagent/reference/calculate_token_warning_state.md)
  or NULL

- `cost_last`: numeric cost of the last turn in USD, or NA_real\_
