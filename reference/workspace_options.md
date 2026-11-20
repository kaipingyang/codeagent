# Workspace options for a codeagent server

Workspace options for a codeagent server

## Usage

``` r
workspace_options(kinds = list(), max_tabs = 12, builtin = TRUE)
```

## Arguments

- kinds:

  A list of
  [`codeagent_workspace_kind()`](https://kaipingyang.github.io/codeagent/reference/codeagent_workspace_kind.md)
  objects.

- max_tabs:

  Most tabs open at once. Opening one more closes the least recently
  viewed tab that is not pinned.

- builtin:

  If `TRUE`, add codeagent's kinds: `result` (a tool result by its
  request id) and `file` (a project file by its path). A host kind with
  the same name replaces a built-in one.

## Value

A `codeagent_workspace_options` object for
`codeagent_server(workspace = )`.
