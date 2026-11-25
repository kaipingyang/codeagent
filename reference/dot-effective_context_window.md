# Effective window after reserving output tokens

Effective window after reserving output tokens

## Usage

``` r
.effective_context_window(model, chat = NULL)
```

## Arguments

- model:

  Character. Model id/name.

- chat:

  An [`ellmer::Chat`](https://ellmer.tidyverse.org/reference/Chat.html)
  or NULL (used to read provider-reported window).

## Value

Integer token count (window minus output reserve).
