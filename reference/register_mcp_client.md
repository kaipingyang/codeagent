# Register external MCP server tools onto a Chat

Register external MCP server tools onto a Chat

## Usage

``` r
register_mcp_client(chat, config = NULL)
```

## Arguments

- chat:

  An [`ellmer::Chat`](https://ellmer.tidyverse.org/reference/Chat.html)
  object.

- config:

  MCP config (path or inline list). See
  [`mcp_client_tools()`](https://github.com/kaipingyang/codeagent/reference/mcp_client_tools.md).

## Value

Invisibly, the number of tools registered.
