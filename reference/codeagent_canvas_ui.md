# Generative UI canvas for a host app

The container
[`codeagent_server()`](https://kaipingyang.github.io/codeagent/reference/codeagent_server.md)
mounts canvas components into, with its "Refresh data" toolbar. Put it
wherever the host wants the canvas (a card, a tab, a sidebar) and pass
the same `canvas` options to
[`codeagent_server()`](https://kaipingyang.github.io/codeagent/reference/codeagent_server.md).
Only one canvas per page. The canvas's Content Security Policy (`csp`)
applies to the whole host page: if the host itself shows external
images, media or frames, pass `canvas_options(csp = FALSE)` or a policy
string that allows them.

## Usage

``` r
codeagent_canvas_ui(canvas = canvas_options())
```

## Arguments

- canvas:

  Options from
  [`canvas_options()`](https://kaipingyang.github.io/codeagent/reference/canvas_options.md).

## Value

A Shiny tag.
