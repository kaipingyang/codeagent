# Create the AskUserQuestion tool

Create the AskUserQuestion tool

## Usage

``` r
ask_user_tool(ask_question_fn = NULL, async = FALSE)
```

## Arguments

  - ask\_question\_fn:
    
    Function or NULL. If provided, called with `(question, choices)`
    instead of `readline()`. Used by the Shiny UI to show an input bar
    and await the user's answer.

  - async:
    
    Logical. When `TRUE`, the tool `fun` is a `coro::async` function
    that `await()`s a promise returned by `ask_question_fn` (Shiny
    path). Requires the chat to be run via
    `stream_async()`/`chat_async()`. Leave `FALSE` for the synchronous
    CLI path (an async fun always returns a promise, which the sync tool
    loop would not await).

## Value

An `ellmer::ToolDef`.
