# Portable tool-result artifacts

**Language:** English \|
[简体中文](https://kaipingyang.github.io/codeagent/articles/tool-artifacts-cn.md)

Tool results serve three different audiences: the model needs portable
text, custom UIs need structured data, and shinychat needs its official
presentation object. codeagent keeps those concerns separate instead of
asking one format to serve all three.

## The three-channel contract

Every result created by
[`tool_result()`](https://kaipingyang.github.io/codeagent/reference/tool_result.md)
is an
[`ellmer::ContentToolResult`](https://ellmer.tidyverse.org/reference/Content.html)
with three deliberately distinct channels:

``` text
ContentToolResult
├── value                         portable model/UI text fallback
├── extra$codeagent$artifact      versioned, UI-neutral structured data
└── extra$display                 optional shinychat presentation adapter
```

The artifact is the primary integration point for a non-shinychat UI.
codeagent projects `display` through
[`shinychat::tool_result_display()`](https://posit-dev.github.io/shinychat/r/reference/tool_result_display.html)
when that official constructor is available; a compatibility fallback
exists only for older installed shinychat versions. The adapter may
contain shinychat-specific HTML and framed-card behavior, so a
third-party host should not parse its presentation HTML.

The `value` remains useful even when an artifact is absent, malformed,
from a future version, or has a kind that the host does not render.

## Artifact v1

A version-1 artifact has this stable outer shape and field order:

``` r

list(
  schema  = "codeagent.tool-artifact",
  version = 1L,
  kind,
  status,
  icon,
  title,
  payload
)
```

| Field | Meaning |
|----|----|
| `schema` | Always `"codeagent.tool-artifact"` for this protocol. |
| `version` | A finite positive whole-number protocol version; v1 is `1L`. |
| `kind` | Rendering category produced by v1: `text`, `table`, `image`, `code`, `diff`, or `error`. |
| `status` | Non-empty result state; v1 producers normally use `success` or `error`. |
| `icon` | Optional portable character icon name. |
| `title` | Optional plain-text character title. |
| `payload` | Kind-specific list of structured data. |

Typical payloads are:

| `kind`  | Typical `payload`                                       |
|---------|---------------------------------------------------------|
| `text`  | `list(text = )`                                         |
| `table` | `list(df = <data.frame>)`                               |
| `image` | `list(images = list(list(mime = , b64 = )), output = )` |
| `code`  | `list(text = , lang = , filename = , output = )`        |
| `diff`  | `list(old = , new = , path = )`                         |
| `error` | `list(message = , detail = )`                           |

A host should tolerate additional payload fields and render only
combinations it explicitly supports.

## Producing a result

Return
[`tool_result()`](https://kaipingyang.github.io/codeagent/reference/tool_result.md)
from an ellmer tool. Its first argument is always the portable value;
rich fields are additive.

``` r

summarise_tool <- ellmer::tool(
  function(group) {
    result <- summarise_data(group)
    codeagent::tool_result(
      value = sprintf("Summary contains %d rows.", nrow(result)),
      kind = "table",
      title = "Grouped summary",
      payload = list(df = result)
    )
  },
  name = "Summarise",
  description = "Summarise data by a group.",
  arguments = list(
    group = ellmer::type_string("Grouping variable.")
  )
)
```

codeagent stores the portable artifact in `extra$codeagent$artifact` and
builds the optional shinychat adapter separately in `extra$display`.
Rich shinychat results request the official framed presentation when the
installed shinychat supports it; this does not change the cross-UI
artifact.

## Consuming results safely

Use the public accessors for both `ContentToolResult` objects and
streaming events. Do not reach through private nesting or parse display
HTML.

``` r

render_result <- function(event_or_result) {
  artifact <- codeagent::tool_result_artifact(event_or_result)

  if (is.null(artifact)) {
    return(render_text(codeagent::tool_result_value(event_or_result)))
  }

  switch(
    artifact$kind,
    table = render_table(artifact$payload$df),
    image = render_images(artifact$payload$images),
    code  = render_code(artifact$payload$text),
    diff  = render_diff(artifact$payload),
    error = render_error(artifact$payload$message),
    render_text(codeagent::tool_result_value(event_or_result))
  )
}
```

[`tool_result_artifact()`](https://kaipingyang.github.io/codeagent/reference/tool_result_artifact.md)
validates the protocol schema and outer shape. Its default is
`version = 1L`; it returns `NULL` when a v1 consumer should fall back to
text. The `version` argument may contain one or more supported positive
whole numbers.
[`tool_result_value()`](https://kaipingyang.github.io/codeagent/reference/tool_result_value.md)
extracts the portable text when possible.

## Streaming callback

[`codeagent_stream()`](https://kaipingyang.github.io/codeagent/reference/codeagent_stream.md)
and
[`codeagent_stream_async()`](https://kaipingyang.github.io/codeagent/reference/codeagent_stream_async.md)
emit this tool-result event with an exact, compatibility-preserving
field order:

``` r

list(
  id,
  name,
  display,
  value,
  is_error,
  artifact
)
```

`artifact` is appended after the original five fields, preserving
positional compatibility. A custom UI normally reads only `artifact`,
`value`, and `is_error`. The `display` field is optional shinychat
presentation data.

``` r

codeagent::codeagent_stream(
  client,
  "Run the summary tool",
  on_tool_result = function(event) {
    artifact <- codeagent::tool_result_artifact(event)
    if (!is.null(artifact) && identical(artifact$kind, "table")) {
      render_table(artifact$payload$df)
    } else {
      render_text(codeagent::tool_result_value(event))
    }
  }
)
```

## Version negotiation

Valid future artifacts are transported unchanged through adaptation and
streaming, but the default v1 accessor rejects them:

``` r

# Safe v1 rendering decision
artifact_v1 <- codeagent::tool_result_artifact(event)

# Protocol inspection or forwarding only; do not render unknown versions
artifact_any <- codeagent::tool_result_artifact(event, version = NULL)
```

A consumer supporting several known versions may pass them explicitly,
for example `version = c(1L, 2L)`. Passing `NULL` disables only the
consumer-version filter; schema and outer-shape validation still apply.
This lets middleware forward a valid future artifact without destroying
it while an older UI reliably falls back to `tool_result_value(event)`.
A UI should opt in to a new version only after implementing that
version’s contract.

Unversioned legacy artifacts can be upgraded to v1 during adaptation.
Malformed metadata is never treated as a valid future protocol: direct
accessor use returns `NULL`, while adaptation may synthesize a valid
value-backed v1 artifact so the portable text remains usable.

## Trust boundary and failure behavior

Artifact data, external display metadata, and restored session metadata
are untrusted input. codeagent therefore follows these rules:

- malformed or unsupported artifacts fail softly to the portable
  `value`;
- plain titles, payload text, Markdown input, and character HTML are
  escaped or placed in escaping tag constructors before browser
  rendering;
- only explicit
  [`htmltools::HTML`](https://rstudio.github.io/htmltools/reference/HTML.html),
  `shiny.tag`, or `shiny.tag.list` objects may cross the trusted-HTML
  boundary;
- `kind = "error"` implies `status = "error"`, and tool/provider error
  metadata forces error status even when a rich image or diff kind is
  retained;
- unrelated request, error, source-provenance, and provider metadata
  survive adaptation;
- malformed display options fall back to a valid artifact-based official
  presentation;
- legacy session cards are promoted on a presentation copy without
  changing the provider-facing value or tool request/result identifiers.

These rules apply to the built-in Shiny UI as well as custom consumers:
the UI may enhance a valid artifact, but it must always retain the
portable value as a safe final fallback.

## Migration checklist

For an existing host integration:

1.  Keep treating `value` as the model-facing and last-resort text
    channel.
2.  Replace `display$toolcard` or `display$right_output` reads with
    [`tool_result_artifact()`](https://kaipingyang.github.io/codeagent/reference/tool_result_artifact.md).
3.  Render only artifact versions and kinds your host explicitly
    supports.
4.  Fall back through
    [`tool_result_value()`](https://kaipingyang.github.io/codeagent/reference/tool_result_value.md)
    for everything else.
5.  Consume `display` only when deliberately integrating with shinychat.

The complete backend callback contract is documented in
[`vignette("backend-integration")`](https://kaipingyang.github.io/codeagent/articles/backend-integration.md).
