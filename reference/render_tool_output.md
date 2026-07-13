# Render a typed tool-result display into an htmltools tag

Branches on `display$toolcard$kind`. Falls back to `right_output`, then
markdown, then a plain `<pre>` so untyped / raw results still render.

## Usage

``` r
render_tool_output(display)
```

## Arguments

  - display:
    
    A `display` list (the `extra$display` of a ContentToolResult).

## Value

An htmltools tag.
