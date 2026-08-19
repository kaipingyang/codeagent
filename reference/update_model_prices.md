# Explicitly update ellmer model pricing data

Downloads ellmer's current public pricing snapshot on demand. codeagent
never calls this function during startup or a model request. A network
failure is returned as a fixed, non-sensitive status instead of
interrupting the app. Custom/private provider endpoints may remain
unpriced after an update.

## Usage

``` r
update_model_prices()
```

## Value

Invisibly, a list with logical `ok`, logical `updated`, and a
human-readable `message`.

## Examples

``` r
if (FALSE) { # \dontrun{
status <- update_model_prices()
status$message
} # }
```
