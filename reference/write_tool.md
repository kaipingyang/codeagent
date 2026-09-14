# Create the Write tool

Create the Write tool

## Usage

``` r
write_tool(mode = "default", rules = list(), ask_fn = NULL, cwd = getwd())
```

## Arguments

- mode:

  Character. Permission mode.

- rules:

  List. Permission rules.

- ask_fn:

  Function or NULL.

- cwd:

  Character. Fixed base directory for relative paths.

## Value

An [`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html)
object.
