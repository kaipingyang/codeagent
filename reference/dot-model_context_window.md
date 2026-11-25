# Resolve a model's raw context window

Resolve a model's raw context window

## Usage

``` r
.model_context_window(model, chat = NULL)
```

## Arguments

- model:

  Character. Model id/name.

- chat:

  An [`ellmer::Chat`](https://ellmer.tidyverse.org/reference/Chat.html)
  or NULL (used to read provider-reported window).

## Value

Integer token count.
