# Browser assets for a host app that embeds codeagent

Registers codeagent's static resource path and returns its `<head>`
assets (input busy state, tool-card styles, syntax highlighting).
Include once in the host UI.

## Usage

``` r
codeagent_head_assets()
```

## Value

A `tags$head()` tag.
