# Extract a versioned tool artifact

Returns codeagent's UI-neutral structured artifact from an
[ellmer::ContentToolResult](https://ellmer.tidyverse.org/reference/Content.html),
an `on_tool_result` event, or an artifact itself. A renderer should
consume supported artifacts first and fall back to
[`tool_result_value()`](https://kaipingyang.github.io/codeagent/reference/tool_result_value.md)
when this function returns `NULL`. The shinychat `extra$display` object
is an optional presentation adapter, not the portable data contract.

## Usage

``` r
tool_result_artifact(result, version = 1L)
```

## Arguments

- result:

  An
  [ellmer::ContentToolResult](https://ellmer.tidyverse.org/reference/Content.html),
  `on_tool_result` event list, or artifact list.

- version:

  Supported artifact version(s). Defaults to version 1. Use `NULL` to
  inspect a structurally valid artifact of any version.

## Value

A `codeagent_tool_artifact`-style list, or `NULL` when absent,
malformed, or unsupported.

## Examples

``` r
result <- tool_result(
  "2 rows", kind = "table",
  payload = list(columns = c("id", "value"), rows = 2L))
artifact <- tool_result_artifact(result)
artifact$kind
#> [1] "table"
artifact$version
#> [1] 1
tool_result_value(result)
#> [1] "2 rows"

# Generic UI fallback pattern:
if (is.null(tool_result_artifact(result))) tool_result_value(result)
```
