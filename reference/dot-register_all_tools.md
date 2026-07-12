# Register all codeagent tools to a Chat object

Register all codeagent tools to a Chat object

## Usage

``` r
.register_all_tools(chat, settings, ask_fn = NULL, ask_question_fn = NULL)
```

## Arguments

- chat:

  An [`ellmer::Chat`](https://ellmer.tidyverse.org/reference/Chat.html)
  object.

- settings:

  Named list from
  [`load_settings()`](https://github.com/kaipingyang/codeagent/reference/load_settings.md).

- ask_fn:

  Function or NULL.

- ask_question_fn:

  Function or NULL. Shiny callback for AskUserQuestion (Phase 3). NULL
  uses CLI readline path.

## Value

Invisibly `chat`.
