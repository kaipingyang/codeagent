# Effective window after reserving output tokens (= getEffectiveContextWindowSize)

Effective window after reserving output tokens (=
getEffectiveContextWindowSize)

## Usage

``` r
.effective_context_window(model, chat = NULL)
```

## Arguments

  - model:
    
    Character. Model id/name.

  - chat:
    
    An `ellmer::Chat` or NULL (used to read provider-reported window).

## Value

Integer token count (window minus output reserve).
