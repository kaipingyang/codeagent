# Exposes codeagent's tool set as an MCP server via `mcptools::mcp_server()`. Session tools are disabled by default because they expose a separate R-session control surface that does not pass through codeagent's Chat permission gate or Data Shield.

Exposes codeagent's tool set as an MCP server via
[`mcptools::mcp_server()`](https://posit-dev.github.io/mcptools/reference/server.html).
Session tools are disabled by default because they expose a separate
R-session control surface that does not pass through codeagent's Chat
permission gate or Data Shield.

## Usage

``` r
codeagent_mcp_server(
  tools = NULL,
  transport = c("stdio", "http"),
  host = "127.0.0.1",
  port = 8000L,
  session_tools = FALSE,
  ...
)
```

## Arguments

- tools:

  Character vector of btw tool groups to expose, or a list of
  [`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html)
  objects. Defaults to all btw tools.

- transport:

  Character. `"stdio"` (default) or `"http"`.

- host:

  Character. Host to bind when `transport = "http"`.

- port:

  Integer. Port to bind when `transport = "http"`.

- session_tools:

  Logical. Expose mcptools R-session controls. Defaults to `FALSE`; may
  only be enabled for stdio or a loopback HTTP listener.

- ...:

  Additional arguments passed to the underlying server function.

## Value

Does not return (blocking).

## Examples

``` r
if (FALSE) { # \dontrun{
# Session controls are disabled unless explicitly requested.
codeagent_mcp_server(session_tools = FALSE)
} # }
```
