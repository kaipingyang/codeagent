# Workspace tabs UI

The tab strip and the tab contents. Place it where the workspace should
show (a sidebar, a drawer, a card) and pass
[`workspace_options()`](https://kaipingyang.github.io/codeagent/reference/workspace_options.md)
to
[`codeagent_server()`](https://kaipingyang.github.io/codeagent/reference/codeagent_server.md).

## Usage

``` r
codeagent_workspace_ui(id = "ca_ws")
```

## Arguments

- id:

  Element id; one workspace per page.

## Value

An htmltools tag.
