# Build a canvas component from an htmlwidget or HTML

`widget` returns any htmlwidget (plotly, leaflet, reactable, ...) or
htmltools tag; it is rendered with
[`shiny::renderUI()`](https://rdrr.io/pkg/shiny/man/renderUI.html), so
no widget-specific output function is needed.

## Usage

``` r
canvas_component_widget(
  name,
  description,
  args = list(),
  widget,
  check = NULL,
  width = c("wide", "auto", "full"),
  data = TRUE,
  code = NULL
)
```

## Arguments

- name:

  Component name; the model calls it as `canvas_<name>`.

- description:

  What the component shows; the model reads it.

- args:

  Named list of ellmer types
  ([`ellmer::type_string()`](https://ellmer.tidyverse.org/reference/type_boolean.html),
  `type_enum()`, `type_integer()`, `type_array()`, ...) for the
  arguments the model fills in. Other ellmer types cannot be
  re-validated on restore and are refused.

- widget:

  `function(args, data)` returning an htmlwidget or tag. `data` is the
  data frame the model named in `dataset` (or `NULL` when
  `data = FALSE`).

- check:

  Optional `function(args, data)` returning `NULL` when the arguments
  fit the data, or a message the model sees when they do not. `data` is
  the data frame itself.

- width:

  One of `"auto"`, `"wide"`, `"full"`.

- data:

  If `TRUE` (default) the tool takes a `dataset` argument naming a data
  frame.

- code:

  Optional `function(args, dataset)` returning standalone R code that
  reproduces the component, used when the canvas is exported.

## Value

A `genui_component`.

## See also

[`canvas_options()`](https://kaipingyang.github.io/codeagent/reference/canvas_options.md),
[`canvas_component_output()`](https://kaipingyang.github.io/codeagent/reference/canvas_component_output.md)
