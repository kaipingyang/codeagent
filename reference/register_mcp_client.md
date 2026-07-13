# Register external MCP server tools onto a Chat

Register external MCP server tools onto a Chat

## Usage

``` r
register_mcp_client(chat, config = NULL)
```

## Arguments

  - chat:
    
    An `ellmer::Chat` object.

  - config:
    
    MCP config (path or inline list). See `mcp_client_tools()`.

## Value

Invisibly, the number of tools registered.
