# Wrap a btw ToolDef with codeagent's permission gate

Uses
[`S7::S7_data()`](https://rconsortium.github.io/S7/reference/S7_data.html)
to extract the underlying R function from a btw `ToolDef` S7 object,
wraps it with a permission checker, then rebuilds a new
[`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html)
preserving the original description, arguments, and annotations.

## Usage

``` r
.wrap_btw_tool_permission(
  btw_tool,
  mode = "default",
  rules = list(),
  ask_fn = NULL
)
```

## Arguments

- btw_tool:

  An
  [`ellmer::ToolDef`](https://ellmer.tidyverse.org/reference/tool.html)
  from
  [`btw::btw_tools()`](https://posit-dev.github.io/btw/reference/btw_tools.html).

- mode:

  Character. Permission mode.

- rules:

  List. Permission rules.

- ask_fn:

  Function or NULL. Interactive ask callback.

## Value

A new
[`ellmer::ToolDef`](https://ellmer.tidyverse.org/reference/tool.html)
with permission gate injected.
