# Render an artifact (typed tool-result data source) into an htmltools tag

Branches on `artifact$kind` (code/image/table/diff/text/error). This is
the single renderer both the in-chat bubble and the right Output panel
use.

## Usage

``` r
render_artifact(artifact, mode = c("panel", "bubble"))
```

## Arguments

- artifact:

  The structured data source: `list(kind, status, icon, title, payload)`
  from `extra$codeagent$artifact`. (Also tolerates being handed a whole
  `display` list carrying a legacy `$toolcard`, for backward-compat.)

- mode:

  `"bubble"` (compact, in-chat) or `"panel"` (full, right Output). Step
  1: accepted but not yet branched – both render identically. Step 2
  will split compact vs full. (plan 35 B1.)

## Value

An htmltools tag.
