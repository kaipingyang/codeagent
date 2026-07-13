# Wrap a btw ToolDef with codeagent's permission gate

Uses `S7::S7_data()` to extract the underlying R function from a btw
`ToolDef` S7 object, wraps it with a permission checker, then rebuilds a
new `ellmer::tool()` preserving the original description, arguments, and
annotations.

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

  - btw\_tool:
    
    An `ellmer::ToolDef` from `btw::btw_tools()`.

  - mode:
    
    Character. Permission mode.

  - rules:
    
    List. Permission rules.

  - ask\_fn:
    
    Function or NULL. Interactive ask callback.

## Value

A new `ellmer::ToolDef` with permission gate injected.
