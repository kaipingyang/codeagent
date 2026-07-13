# Build a typed ContentToolResult

Superset of the legacy `.tool_result()`: in addition to
`title`/`markdown`, carries a typed `card` payload consumed by
[`render_tool_output()`](https://kaipingyang.github.io/codeagent/reference/render_tool_output.md)
and eagerly precomputes `right_output` so the existing server push path
keeps working.

## Usage

``` r
.tool_result2(
  text,
  kind = "text",
  status = "success",
  icon = NULL,
  title = NULL,
  payload = list(),
  markdown = NULL
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

  bsicons name (character) for the in-chat card + right panel.

- title:

  Character or HTML. Card title (HTML allowed for the in-chat card).

- payload:

  List. Kind-specific data (see file docs).

- markdown:

  Character. In-chat card body + two-phase fallback.

## Value

An
[`ellmer::ContentToolResult`](https://ellmer.tidyverse.org/reference/Content.html).
