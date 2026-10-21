# Configure the generative UI canvas

Choose which components the canvas in
[`codeagent_app()`](https://kaipingyang.github.io/codeagent/reference/codeagent_app.md)
offers and how strictly model-authored text is checked. Components are
the same objects shinygenui uses
([`shinygenui::genui_component()`](https://nanx.me/shinygenui/reference/genui_component.html));
build your own with
[`canvas_component_output()`](https://kaipingyang.github.io/codeagent/reference/canvas_component_output.md)
or
[`canvas_component_widget()`](https://kaipingyang.github.io/codeagent/reference/canvas_component_widget.md),
or pass any existing `genui_component`.

## Usage

``` r
canvas_options(
  components = list(),
  starter = TRUE,
  data_env = globalenv(),
  csp = TRUE,
  validate_text = TRUE
)
```

## Arguments

- components:

  A list of `genui_component` objects supplied by the host.

- starter:

  Which of shinygenui's own components to offer: `TRUE` (all of them,
  the default), `FALSE` (none), or a character vector of their names
  (`"value_box"`, `"data_table"`, `"scatter_plot"`, `"histogram"`,
  `"markdown_card"`, `"card_row"`).

- data_env:

  Environment in which `dataset` names are looked up.

- csp:

  Content Security Policy for the page while the canvas is available:
  `TRUE` (default; images, media, frames and plugins only from the app
  itself), `FALSE` (none), or a policy string of your own – for example
  when a component loads map tiles from another origin.

- validate_text:

  If `TRUE` (default), every string the model passes to a canvas tool is
  refused when it contains markup, links, URLs or control characters,
  before anything reaches the browser. This guards against the model (or
  a prompt injection) placing data in a URL the browser would fetch. Set
  `FALSE` when your components need the model to supply URLs.

## Value

A `codeagent_canvas_options` object for `codeagent_app(canvas = )`.

## Details

Host components are trusted code: codeagent registers them as canvas
tools (read-only, behind the central permission gate), runs them through
the same transactional executor, Data Shield scanning and strict session
restore as the built-in ones, and leaves what they render to you.

## See also

[`canvas_component_output()`](https://kaipingyang.github.io/codeagent/reference/canvas_component_output.md),
[`canvas_component_widget()`](https://kaipingyang.github.io/codeagent/reference/canvas_component_widget.md)

## Examples

``` r
if (FALSE) { # \dontrun{
boxplot_card <- canvas_component_output(
  "boxplot", "Box plot of a numeric column by group.",
  args = list(y = ellmer::type_string("Numeric column."),
              by = ellmer::type_string("Grouping column.")),
  output = shiny::plotOutput,
  render = function(args, data) shiny::renderPlot(
    boxplot(reformulate(args$by, args$y), data = data())))
codeagent_app(chat, canvas = canvas_options(
  components = list(boxplot_card), starter = c("data_table", "histogram")))
} # }
```
