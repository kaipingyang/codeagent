# Exposes codeagent's tool set as an MCP server. By default uses btw's `btw_mcp_server()` over stdio (for Claude Desktop / VS Code MCP config). With `transport = "http"` it serves over HTTP via `mcptools::mcp_server()` (\>= 0.2.1), enabling remote MCP clients. The server runs in a blocking loop.

Exposes codeagent's tool set as an MCP server. By default uses btw's
`btw_mcp_server()` over stdio (for Claude Desktop / VS Code MCP config).
With `transport = "http"` it serves over HTTP via
`mcptools::mcp_server()` (\>= 0.2.1), enabling remote MCP clients. The
server runs in a blocking loop.

## Usage

``` r
codeagent_mcp_server(
  tools = NULL,
  transport = c("stdio", "http"),
  host = "127.0.0.1",
  port = 8000L,
  ...
)
```

## Arguments

  - tools:
    
    Character vector of btw tool groups to expose, or a list of
    `ellmer::tool()` objects. Defaults to all btw tools.

  - transport:
    
    Character. `"stdio"` (default) or `"http"`.

  - host:
    
    Character. Host to bind when `transport = "http"`.

  - port:
    
    Integer. Port to bind when `transport = "http"`.

  - ...:
    
    Additional arguments passed to the underlying server function.

## Value

Does not return (blocking).
