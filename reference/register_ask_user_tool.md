# Register the AskUserQuestion tool on a Chat

Register the AskUserQuestion tool on a Chat

## Usage

``` r
register_ask_user_tool(chat, ask_question_fn = NULL, async = FALSE)
```

## Arguments

- chat:

  An [`ellmer::Chat`](https://ellmer.tidyverse.org/reference/Chat.html)
  object.

- ask_question_fn:

  Function or NULL. Shiny callback for Phase 3.

- async:

  Logical. Build the async (promise-awaiting) variant (Shiny).

## Value

Invisibly `chat`.
