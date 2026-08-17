# Build a rich tool result (typed display card) for a host tool

Construct an
[ellmer::ContentToolResult](https://ellmer.tidyverse.org/reference/Content.html)
that carries a **typed display card**, so a tool's output renders as a
table / image / code / error / rich text both in codeagent's Shiny app
and in any host UI that consumes the `on_tool_result$display` callback
of
[`codeagent_stream()`](https://kaipingyang.github.io/codeagent/reference/codeagent_stream.md).

`value` is the text the model sees; `payload` carries the rich artifact
for the UI. Return the result from your tool's function body.

A host UI reads `extra$codeagent$artifact$kind` + `...$payload` (the
structured artifact, e.g. `payload$df` for a table); codeagent's Shiny
app additionally receives a pre-rendered `display$html`.

## Usage

``` r
tool_result(
  value,
  kind = c("text", "table", "image", "code", "diff", "error"),
  payload = list(),
  title = NULL,
  icon = NULL,
  status = c("success", "error"),
  markdown = NULL
)
```

## Arguments

- value:

  Character(1). Text summary returned to the model.

- kind:

  One of `"text"`, `"table"`, `"image"`, `"code"`, `"diff"`, `"error"`.

- payload:

  Named list holding the artifact, keyed by `kind`:

  - `table`: `list(df = <data.frame>)`

  - `image`:
    `list(images = list(list(mime = "image/png", b64 = <string>)), output = <text>)`

  - `code` : `list(text = <code>, lang = , filename = , output = )`

  - `error`: `list(message = , detail = )`

  - `text` : `list(text = )`

- title, icon:

  Optional card title / icon name.

- status:

  One of `"success"`, `"error"` (forced to `"error"` when
  `kind = "error"`).

- markdown:

  Optional markdown string attached to the display.

## Value

An
[ellmer::ContentToolResult](https://ellmer.tidyverse.org/reference/Content.html);
return it from your tool function.

## See also

[`codeagent_stream()`](https://kaipingyang.github.io/codeagent/reference/codeagent_stream.md),
[`register_tool_meta()`](https://kaipingyang.github.io/codeagent/reference/register_tool_meta.md)

## Examples

``` r
if (FALSE) { # \dontrun{
summarise <- ellmer::tool(
  function(data_name) {
    df <- summary_frame(data_name)
    tool_result(sprintf("%d x %d summary", nrow(df), ncol(df)),
                kind = "table", payload = list(df = df),
                title = "Summary")
  },
  name = "Summarise", description = "...", arguments = list(...))
chat$register_tool(summarise)
register_tool_meta("Summarise", "read")
} # }
```
