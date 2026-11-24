# Run codeagent's chat engine inside a host Shiny app

Wires the same server side that
[`codeagent_app()`](https://kaipingyang.github.io/codeagent/reference/codeagent_app.md)
uses – streaming with per-turn compaction, stop / ESC interrupt,
`/skill` commands, hooks, token budget and per-turn session saving; the
approval and question bar (`AskUserQuestion`); the generative UI canvas;
and Data Shield – to a client the host built for this Shiny session.
Pair it with
[`codeagent_chat_ui()`](https://kaipingyang.github.io/codeagent/reference/codeagent_chat_ui.md)
and
[`codeagent_head_assets()`](https://kaipingyang.github.io/codeagent/reference/codeagent_head_assets.md),
and with
[`codeagent_canvas_ui()`](https://kaipingyang.github.io/codeagent/reference/codeagent_canvas_ui.md)
when `canvas` is given.

## Usage

``` r
codeagent_server(
  input,
  output,
  session,
  client,
  tools = list(),
  tool_meta = list(),
  canvas = NULL,
  history = NULL,
  greeting = NULL,
  modes = NULL,
  on_restore = NULL,
  on_tool_open = NULL,
  on_user_prompt = NULL,
  workspace = NULL,
  sessions = FALSE,
  themes = NULL,
  on_theme = NULL
)
```

## Arguments

- input, output, session:

  The Shiny server arguments.

- client:

  A
  [`codeagent_client()`](https://kaipingyang.github.io/codeagent/reference/codeagent_client.md)
  built for this session.

- tools:

  Host tools (a list of
  [`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html)
  definitions). Each must have a capability in `tool_meta`. They are
  registered after the built-in tools, with codeagent's result
  normalization, behind the permission gate and Data Shield.

- tool_meta:

  Named list or character vector: host tool name -\> capability
  (`"read"`, `"write"`, `"exec"` or `"net"`).

- canvas:

  `NULL` (no canvas) or
  [`canvas_options()`](https://kaipingyang.github.io/codeagent/reference/canvas_options.md)
  to enable the generative UI canvas; place
  [`codeagent_canvas_ui()`](https://kaipingyang.github.io/codeagent/reference/codeagent_canvas_ui.md)
  in the page. With a `tools=` selection on the client, include
  `"genui"` in it.

- history:

  Conversation history: `NULL` (default, none);
  [`shinychat::history_options()`](https://posit-dev.github.io/shinychat/r/reference/history_options.html)
  for shinychat's history (list, switch, new, rename, delete in the
  chat's history selector – set `codeagent_chat_ui(history = TRUE)`); or
  `"codeagent"` for codeagent's own list
  ([`codeagent_sessions_ui()`](https://kaipingyang.github.io/codeagent/reference/codeagent_sessions_ui.md)).
  With shinychat's history the record holds what the user saw (Data
  Shield output gate applied, no injected context) and is not shortened
  by compaction; the model continues from codeagent's session log
  ([`save_session()`](https://kaipingyang.github.io/codeagent/reference/save_session.md)).

- greeting:

  With `history`: the greeting shown again on a new conversation (the
  one given to
  [`codeagent_chat_ui()`](https://kaipingyang.github.io/codeagent/reference/codeagent_chat_ui.md)).

- modes:

  `NULL` (the client's permission mode, fixed) or the named modes of
  [`codeagent_mode_ui()`](https://kaipingyang.github.io/codeagent/reference/codeagent_mode_ui.md)
  (place it in the page): the user switches the session's permission
  mode between them; not while a reply is running.

- on_restore:

  Optional `function(chat)` called after a saved conversation is opened
  from the history (either backend), with the Chat holding the restored
  context – e.g. to show its last result in the host's own panels.

- on_tool_open:

  Optional `function(result)` called when the user opens (expands) a
  tool card in the chat – live or in a restored conversation – with that
  card's
  [`ellmer::ContentToolResult`](https://ellmer.tidyverse.org/reference/Content.html),
  e.g. to show the result in the host's own panel. Only results with an
  HTML display (`extra$display$html`) are reported.

- on_user_prompt:

  Optional `function(text)` called with what the user typed before each
  turn reaches the model – the host side of Claude Code's
  `UserPromptSubmit` hook. Return `NULL` to proceed unchanged, a
  character string to add it as context to this turn (the user's text is
  never changed), or `list(action = "block", message = )` to stop the
  turn. Typical use: facts the host knows that save the model a tool
  call (e.g. what a project contains), sent once with the first turn.

- workspace:

  `NULL` (no workspace tabs) or
  [`workspace_options()`](https://kaipingyang.github.io/codeagent/reference/workspace_options.md):
  place
  [`codeagent_workspace_ui()`](https://kaipingyang.github.io/codeagent/reference/codeagent_workspace_ui.md)
  in the page. Each opened tool result, file or host content gets its
  own tab; open tabs with the returned `ws`. Without an `on_tool_open`,
  opening a tool card in the chat opens its result tab.

- sessions:

  Deprecated: `TRUE` is `history = "codeagent"`.

- themes:

  `NULL` (the page keeps its theme) or a named list, theme name -\> a
  bslib theme or a
  [`codeagent_theme()`](https://kaipingyang.github.io/codeagent/reference/codeagent_theme.md)
  style name (e.g.
  `list(default = bslib::bs_theme(version = 5), dsh = "dsh")`); place
  [`codeagent_theme_ui()`](https://kaipingyang.github.io/codeagent/reference/codeagent_theme_ui.md)
  with the same names in the page. The user switches the page's theme
  while the session runs; the page structure, chat and tabs stay. The
  page must be built with a bslib theme.

- on_theme:

  Optional `function(name)` called after the user switched the theme,
  e.g. to remember the choice for their next visit.

## Value

Invisibly, a list with `state` (the session `reactiveValues`),
`stream_task` (the `ExtendedTask`), `chat`, `settings` and, with
`workspace`, `ws`:
`ws$open(kind, content_id, title = NULL, reveal = TRUE)`,
`ws$close(tab)`, `ws$focus(tab)`, `ws$pin(tab, pinned = TRUE)`, and the
reactive reads `ws$active()` and `ws$tabs()`.

## Details

Build the client per session with
`codeagent_client(..., register_tools = FALSE)`; tools are registered
once the UI has flushed, after the Shiny approval / question callbacks
exist, so the interactive tools are created in their UI-gated form.
Select built-in tools with the client's `tools=`.

## See also

[`codeagent_chat_ui()`](https://kaipingyang.github.io/codeagent/reference/codeagent_chat_ui.md),
[`codeagent_canvas_ui()`](https://kaipingyang.github.io/codeagent/reference/codeagent_canvas_ui.md),
[`codeagent_sessions_ui()`](https://kaipingyang.github.io/codeagent/reference/codeagent_sessions_ui.md),
[`codeagent_app()`](https://kaipingyang.github.io/codeagent/reference/codeagent_app.md)
