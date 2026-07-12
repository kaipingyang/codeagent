# Wrap an ellmer Chat with codeagent settings into a client object

Wrap an ellmer Chat with codeagent settings into a client object

## Usage

``` r
.new_client(chat, settings)
```

## Arguments

- chat:

  Ellmer Chat object (already equipped with tools and system prompt).

- settings:

  Named list from
  [`load_settings()`](https://github.com/kaipingyang/codeagent/reference/load_settings.md).

## Value

Object of class `CodeagentClient`.
