# Auto-connect MCP servers from settings / project config

NOTE: Project-level and merged settings CANNOT authorise MCP startup
(V-08 remedy). This function only connects when the host has explicitly
provided `mcp_config` to
[`codeagent_client()`](https://kaipingyang.github.io/codeagent/reference/codeagent_client.md).
Settings-file servers and project `.mcp.json` are NOT auto-connected –
the caller must migrate to the explicit `mcp_config` parameter and
review the server configurations.

## Usage

``` r
.mcp_autoconnect(chat, settings)
```

## Arguments

- chat:

  An [`ellmer::Chat`](https://ellmer.tidyverse.org/reference/Chat.html)
  object.

- settings:

  List from
  [`load_settings()`](https://kaipingyang.github.io/codeagent/reference/load_settings.md).

## Value

Invisibly, the number of tools registered (always 0 – auto-connect is
disabled).
