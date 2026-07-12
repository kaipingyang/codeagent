# Register notebook tools to an ellmer Chat object

Register notebook tools to an ellmer Chat object

## Usage

``` r
register_notebook_tools(chat, mode = "default", rules = list(), ask_fn = NULL)
```

## Arguments

- chat:

  An [`ellmer::Chat`](https://ellmer.tidyverse.org/reference/Chat.html)
  object.

- mode:

  Character. Permission mode.

- rules:

  List. Permission rules.

- ask_fn:

  Function or NULL.

## Value

Invisibly returns `chat`.
