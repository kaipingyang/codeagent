# MCP Client (connect to external MCP servers)

Registers tools exposed by external Model Context Protocol servers onto
a codeagent Chat, via `mcptools::mcp_tools()`. This is the client side
(consuming external tools); `codeagent_mcp_server()` is the server side
(exposing codeagent's tools).

Transport: mcptools (\>= 0.2.1) launches stdio MCP servers as child
processes (`command` + `args` + `env` per the config) on the **client**
side. Remote HTTP/SSE *client* connections are not yet supported
upstream (mcptools `mcp_tools()` is stdio-only); codeagent can however
*serve* over HTTP – see `codeagent_mcp_server()` with `transport =
"http"`.

Config format (JSON file or inline list), e.g.:

    {
      "mcpServers": {
        "filesystem": {
          "command": "npx",
          "args": ["-y", "@modelcontextprotocol/server-filesystem", "/workspace"]
        }
      }
    }
