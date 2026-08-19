# Swap only a Chat's model name in place (strict Route A)

Route A is allowed only when provider configuration is unchanged and the
target Model differs solely by name. Cross-provider, endpoint,
credentials, params, and extra-argument changes return `FALSE` without
mutation.

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
  describing the requested target.

## Value

Logical. `TRUE` only after the post-switch state is verified.
