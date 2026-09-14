# Create the Grep tool

Uses `rg` (ripgrep) if available, falls back to base R `grep`.

## Usage

``` r
grep_tool(cwd = getwd())
```

## Arguments

- cwd:

  Character. Fixed base directory for relative paths.

## Value

An [`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html)
object.
