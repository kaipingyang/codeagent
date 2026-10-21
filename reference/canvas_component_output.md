# Build a canvas component from a Shiny output

Wraps any `*Output()` / `render*()` pair – base Shiny, or a package such
as plotly (`plotlyOutput` / `renderPlotly`) – as a canvas component.

## Usage

``` r
canvas_component_output(
  name,
  description,
  args = list(),
  output,
  render,
  check = NULL,
  width = c("auto", "wide", "full"),
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

- output:

  An output constructor taking an output id, e.g.
  [`shiny::plotOutput`](https://rdrr.io/pkg/shiny/man/plotOutput.html).

- render:

  `function(args, data)` returning a render function, e.g.
  `shiny::renderPlot(...)`. `data` is a function returning the data
  frame the model named in `dataset` (or `NULL` when `data = FALSE`).

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
[`canvas_component_widget()`](https://kaipingyang.github.io/codeagent/reference/canvas_component_widget.md)
