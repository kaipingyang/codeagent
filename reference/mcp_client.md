# MCP Client (connect to external MCP servers)

Registers tools exposed by external Model Context Protocol servers onto
a codeagent Chat, via
[`mcptools::mcp_tools()`](https://posit-dev.github.io/mcptools/reference/client.html).
This is the client side (consuming external tools);
[`codeagent_mcp_server()`](https://kaipingyang.github.io/codeagent/reference/codeagent_mcp_server.md)
is the server side (exposing codeagent's tools).

Transport: mcptools (\>= 1.0.2.9000) launches stdio MCP servers as child
processes (`command` + `args` + `env`) and connects directly to remote
Streamable HTTP servers configured with `url`. Static headers and MCP
OAuth discovery/PKCE/token refresh are handled upstream by
`mcp_tools()`; codeagent passes the config through without persisting
credentials.

Config format (JSON file or inline list), e.g.:

    {
      "mcpServers": {
        "filesystem": {
          "command": "npx",
          "args": ["-y", "@modelcontextprotocol/server-filesystem", "/workspace"]
        }
      }
    }
