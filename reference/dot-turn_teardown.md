# Run per-turn teardown: save session and return usage + cost.

Run per-turn teardown: save session and return usage + cost.

## Usage

``` r
.turn_teardown(client, cwd = NULL, session_id = NULL)
```

## Arguments

  - client:
    
    A `CodeagentClient` or bare `ellmer::Chat`.

  - cwd:
    
    Character or NULL.

  - session\_id:
    
    Character or NULL.

## Value

Named list with elements:

  - `n_tokens`: integer token count (real or estimated)

  - `model_limit`: integer context window limit

  - `warning_state`: list from `calculate_token_warning_state()` or NULL

  - `cost_last`: numeric cost of the last turn in USD, or NA\_real\_
