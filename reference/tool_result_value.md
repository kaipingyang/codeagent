# Extract the portable text fallback from a tool result

Works with an
[ellmer::ContentToolResult](https://ellmer.tidyverse.org/reference/Content.html),
an `on_tool_result` event, or a character value. Third-party UIs should
display this value whenever they do not support the result's artifact
schema/version/kind.

## Usage

``` r
tool_result_value(result, default = "")
```

## Arguments

- result:

  An
  [ellmer::ContentToolResult](https://ellmer.tidyverse.org/reference/Content.html),
  `on_tool_result` event list, or character value.

- default:

  Character fallback used when no value can be extracted.

## Value

A character scalar.

## See also

[`tool_result_artifact()`](https://kaipingyang.github.io/codeagent/reference/tool_result_artifact.md),
[`tool_result()`](https://kaipingyang.github.io/codeagent/reference/tool_result.md)
