# Register all codeagent tools to a Chat object

Register all codeagent tools to a Chat object

## Usage

``` r
.register_all_tools(chat, settings, ask_fn = NULL, ask_question_fn = NULL)
```

## Arguments

  - chat:
    
    An `ellmer::Chat` object.

  - settings:
    
    Named list from `load_settings()`.

  - ask\_fn:
    
    Function or NULL.

  - ask\_question\_fn:
    
    Function or NULL. Shiny callback for AskUserQuestion (Phase 3). NULL
    uses CLI readline path.

## Value

Invisibly `chat`.
