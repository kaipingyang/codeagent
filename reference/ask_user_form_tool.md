# Create the AskUserForm tool

Create the AskUserForm tool

## Usage

``` r
ask_user_form_tool(ask_form_fn = NULL, async = FALSE)
```

## Arguments

- ask_form_fn:

  Function or NULL. If provided, called with
  `(title, fields, submit_label)` and returns (a promise of) a list with
  `submitted` (logical) and `values` (named list). Used by the Shiny UI.

- async:

  Logical. Build the
  [`coro::async`](https://coro.r-lib.org/reference/async.html) variant
  that awaits the promise from `ask_form_fn` (Shiny, `stream_async()`);
  `FALSE` for the synchronous CLI path.

## Value

An
[`ellmer::ToolDef`](https://ellmer.tidyverse.org/reference/ToolDef.html).

## See also

[`ask_user_tool()`](https://kaipingyang.github.io/codeagent/reference/ask_user_tool.md)
