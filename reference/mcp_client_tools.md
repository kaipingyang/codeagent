# Load tools from external MCP servers

Load tools from external MCP servers

## Usage

``` r
mcp_client_tools(config = NULL)
```

## Arguments

  - config:
    
    Path to an MCP config JSON file, or an inline list with the same
    shape. `NULL` uses mcptools' default config location.

## Value

A list of `ellmer::tool()` objects (empty list on failure).
