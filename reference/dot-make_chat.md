# Create a bare ellmer Chat from settings

Create a bare ellmer Chat from settings

## Usage

``` r
.make_chat(settings, cwd = getwd(), ...)
```

## Arguments

- settings:

  List. Output of
  [`load_settings()`](https://github.com/kaipingyang/codeagent/reference/load_settings.md).

- cwd:

  Character. Working directory.

- ...:

  Passed to the underlying ellmer function.

## Value

An [`ellmer::Chat`](https://ellmer.tidyverse.org/reference/Chat.html)
object.
