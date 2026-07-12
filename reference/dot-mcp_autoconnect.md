# Auto-connect MCP servers from settings / project config

Connects external MCP servers without an explicit `mcp_config` argument,
by looking (in order) at:

1.  `settings$mcpServers` / `settings$mcp_servers` – an inline server
    map in settings.json.

2.  a project-level `.mcp.json` / `.codeagent/mcp.json` file.

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
  [`load_settings()`](https://github.com/kaipingyang/codeagent/reference/load_settings.md).

## Value

Invisibly, the number of tools registered.

## Details

`enabled_mcp_json_servers` / `disabled_mcp_json_servers` (Claude Code
schema) filter which named servers are connected. Servers already
provided via the `mcp_config` parameter to
[`codeagent_client()`](https://github.com/kaipingyang/codeagent/reference/codeagent_client.md)
are handled separately and not duplicated here.
