# Register the AskUserForm tool on a Chat

Register the AskUserForm tool on a Chat

## Usage

``` r
register_ask_user_form_tool(chat, ask_form_fn = NULL, async = FALSE)
```

## Arguments

- chat:

  An [`ellmer::Chat`](https://ellmer.tidyverse.org/reference/Chat.html)
  object.

- ask_form_fn:

  Function or NULL. Shiny callback (see
  [`ask_user_form_tool()`](https://kaipingyang.github.io/codeagent/reference/ask_user_form_tool.md)).

- async:

  Logical. Build the async (promise-awaiting) variant (Shiny).

## Value

Invisibly `chat`.
