# Swap a Chat's provider in place (Route A)

When the new model uses the same provider class (e.g. both
OpenAI-compatible), uses the public `set_model()` API added in ellmer
0.4.2. For cross-provider switches (e.g. OpenAI-compat -\> Anthropic)
falls back to replacing the private R6 `private$provider` field – still
necessary until ellmer adds `set_provider()` (see
https://github.com/tidyverse/ellmer/issues/1042). Returns TRUE on
success, FALSE if inaccessible.

## Usage

``` r
.swap_provider(chat, new_chat)
```

## Arguments

- chat:

  An [`ellmer::Chat`](https://ellmer.tidyverse.org/reference/Chat.html)
  to mutate.

- new_chat:

  An [`ellmer::Chat`](https://ellmer.tidyverse.org/reference/Chat.html)
  whose provider to adopt.

## Value

Logical. TRUE if swapped in place.
