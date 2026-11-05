# Saved conversations for a host app that embeds codeagent

The list of this workspace's saved conversations (newest first, by their
first message) with "New" and "Delete" buttons, as in
[`codeagent_app()`](https://kaipingyang.github.io/codeagent/reference/codeagent_app.md)'s
Sessions panel. Clicking one restores it into the chat – tool cards and
the canvas included. Put it wherever the host wants it (a sidebar, an
accordion) and pass `sessions = TRUE` to
[`codeagent_server()`](https://kaipingyang.github.io/codeagent/reference/codeagent_server.md).
Only one per page.

## Usage

``` r
codeagent_sessions_ui(title = "History")
```

## Arguments

- title:

  Heading above the list, or `NULL` for none.

## Value

A Shiny tag.

## Details

Conversations are saved per turn under `CODEAGENT_HOME`, keyed by the
client's working directory (`cwd`): give each user a fixed `cwd` so the
list survives a restart of the app process and holds only that user's
conversations. A page always opens on a new conversation.

## See also

[`codeagent_server()`](https://kaipingyang.github.io/codeagent/reference/codeagent_server.md)
