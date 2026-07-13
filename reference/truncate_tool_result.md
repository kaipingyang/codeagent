# Truncate a tool result to the per-tool character limit

Part of the three-layer resource management system. Layer 1 limits
single tool call output size.

## Usage

``` r
truncate_tool_result(content, tool_name = "default")
```

## Arguments

- content:

  Character(1). Tool output.

- tool_name:

  Character(1). Tool name for limit lookup.

## Value

Character(1). Possibly truncated content with a note appended.
