# Create an R-based MCP server entry

Builds an `mcp_servers` list entry that launches an R subprocess running
[`mcptools::mcp_server()`](https://posit-dev.github.io/mcptools/reference/server.html)
over stdio.

## Usage

``` r
r_mcp_server(
  tools_script = NULL,
  session_tools = FALSE,
  rscript = file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe"
    else "Rscript")
)
```

## Arguments

- tools_script:

  Character(1) or NULL. Path to an `.R` script that yields a
  [`list()`](https://rdrr.io/r/base/list.html) of
  [`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html)
  objects.

- session_tools:

  Logical. Whether to expose built-in mcptools session management tools.
  Default `FALSE`.

- rscript:

  Character(1). Path to the `Rscript` binary.

## Value

A named list with `type`, `command`, and `args`.
