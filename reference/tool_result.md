# Build a versioned cross-UI tool result

Construct an
[ellmer::ContentToolResult](https://ellmer.tidyverse.org/reference/Content.html)
with three independent channels: `value` is portable model-facing text;
`extra$codeagent$artifact` is the versioned, UI-neutral structured
result; and `extra$display` is shinychat's official presentation
adapter. Return the result from your tool function.

Non-shinychat hosts should read the artifact with
[`tool_result_artifact()`](https://kaipingyang.github.io/codeagent/reference/tool_result_artifact.md),
render supported `kind`/`payload` combinations natively, and use
[`tool_result_value()`](https://kaipingyang.github.io/codeagent/reference/tool_result_value.md)
as the fallback. They never need to parse shinychat HTML. The streaming
`on_tool_result` event exposes the same `artifact`, `display`, and
`value` channels.

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
