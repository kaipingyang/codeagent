# Build a typed ContentToolResult

Compatibility name for codeagent's original typed-result constructor.
New internal code uses `.artifact_tool_result()`; this forwards without
creating a second display protocol.

## Usage

``` r
.tool_result2(
  text,
  kind = "text",
  status = "success",
  icon = NULL,
  title = NULL,
  payload = list(),
  markdown = NULL,
  footer = NULL,
  label = NULL,
  value_preview = NULL
)
```

## Arguments

- text:

  Character. LLM-facing value.

- kind:

  One of `"code"`, `"image"`, `"table"`, `"diff"`, `"text"`, `"error"`.

- status:

  One of `"success"`, `"error"`, `"denied"`.

- icon:

  Icon name used by UI adapters.

- title:

  Character or HTML display title.

- payload:

  List of kind-specific artifact data.

- markdown:

  Optional shinychat markdown body.

- footer:

  Optional shinychat footer content.

- label:

  Optional compact activity label.

- value_preview:

  Optional compact result preview.

## Value

An
[`ellmer::ContentToolResult`](https://ellmer.tidyverse.org/reference/Content.html).
