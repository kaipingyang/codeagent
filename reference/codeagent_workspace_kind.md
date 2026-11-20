# Declare a kind of workspace tab

A kind says how a tab of that kind renders. Pass kinds to
[`workspace_options()`](https://kaipingyang.github.io/codeagent/reference/workspace_options.md);
open tabs with the `ws` object
[`codeagent_server()`](https://kaipingyang.github.io/codeagent/reference/codeagent_server.md)
returns (`ws$open(kind, content_id)`).

## Usage

``` r
codeagent_workspace_kind(kind, render, title = NULL, pinned = FALSE)
```

## Arguments

- kind:

  Name of the kind, e.g. `"tfl"`.

- render:

  `function(content_id, session)` returning UI for one tab. It runs
  inside a `renderUI()`, so it may read reactive values.

- title:

  Optional `function(content_id)` giving the tab title when the caller
  does not pass one.

- pinned:

  If `TRUE`, one tab of this kind (content id = the kind name) opens
  when the workspace starts, sorts first and cannot be closed.

## Value

A `codeagent_workspace_kind` object.
