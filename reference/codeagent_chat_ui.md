# Chat UI for a host app that embeds codeagent

A
[`shinychat::chat_ui()`](https://posit-dev.github.io/shinychat/r/reference/chat_ui.html)
configured the way
[`codeagent_server()`](https://kaipingyang.github.io/codeagent/reference/codeagent_server.md)
expects: the input id is `"chat"`, the approval / question bar sits
above the input (it renders into output `ca_interaction_ui`), cancel is
enabled, and tool calls are grouped per tool. Place it anywhere in the
host page, together with
[`codeagent_head_assets()`](https://kaipingyang.github.io/codeagent/reference/codeagent_head_assets.md).

## Usage

``` r
codeagent_chat_ui(..., greeting = NULL, footer = NULL)
```

## Arguments

- ...:

  Further arguments passed to
  [`shinychat::chat_ui()`](https://posit-dev.github.io/shinychat/r/reference/chat_ui.html);
  they override the defaults described above (except `id`).

- greeting:

  Optional greeting (markdown or HTML string, or a
  [`shinychat::chat_greeting()`](https://posit-dev.github.io/shinychat/r/reference/chat_greeting.html)).
  A string is shown as a persistent greeting.

- footer:

  Optional extra UI placed under the interaction bar.

## Value

A Shiny tag.

## See also

[`codeagent_server()`](https://kaipingyang.github.io/codeagent/reference/codeagent_server.md),
[`codeagent_canvas_ui()`](https://kaipingyang.github.io/codeagent/reference/codeagent_canvas_ui.md)
