# Open codeagent with the current editor selection as context

Reads the selected text in the active RStudio/Positron source editor and
opens
[`codeagent_app()`](https://kaipingyang.github.io/codeagent/reference/codeagent_app.md)
with that code pre-loaded as context. Works in both RStudio and Positron
(both support `rstudioapi`).

## Usage

``` r
codeagent_addin_selection()
```

## Value

Invisibly NULL.
