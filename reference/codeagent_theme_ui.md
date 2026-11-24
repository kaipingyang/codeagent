# Skin switch for a host app

A small radio group the user switches the page's theme with. Pass the
same names to
[`codeagent_server()`](https://kaipingyang.github.io/codeagent/reference/codeagent_server.md)'s
`themes`. The page must be built with a bslib theme
([`bslib::bs_theme()`](https://rstudio.github.io/bslib/reference/bs_theme.html),
[`codeagent_theme()`](https://kaipingyang.github.io/codeagent/reference/codeagent_theme.md))
for its theme to be swapped. Only one per page.

## Usage

``` r
codeagent_theme_ui(
  themes = c(Default = "default", DSH = "dsh"),
  selected = NULL,
  label = NULL
)
```

## Arguments

- themes:

  Named character vector: label -\> theme name (a name of
  `codeagent_server(themes =)`), e.g.
  `c(Default = "default", DSH = "dsh")`.

- selected:

  The theme selected at start (default: the first) – the one the page
  was built with.

- label:

  Optional label shown before the choices.

## Value

A Shiny tag.

## See also

[`codeagent_server()`](https://kaipingyang.github.io/codeagent/reference/codeagent_server.md),
[`codeagent_theme()`](https://kaipingyang.github.io/codeagent/reference/codeagent_theme.md)
