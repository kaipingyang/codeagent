# Resolve a model's raw context window (= getContextWindowForModel, context.ts:51)

Resolve a model's raw context window (= getContextWindowForModel,
context.ts:51)

## Usage

``` r
.model_context_window(model, chat = NULL)
```

## Arguments

  - model:
    
    Character. Model id/name.

  - chat:
    
    An `ellmer::Chat` or NULL (used to read provider-reported window).

## Value

Integer token count.
