# Open the codeagent Shiny app from an IDE addin

Registers as an RStudio/Positron addin. Builds a client from the user's
settings and launches
[`codeagent_app()`](https://kaipingyang.github.io/codeagent/reference/codeagent_app.md).
Optionally pre-fills the first user message with any text currently
selected in the source editor.

## Usage

``` r
codeagent_addin(selection = NULL)
```

## Arguments

- selection:

  Character or NULL. Pre-fill text. When NULL (default in the plain chat
  addin) the app opens with an empty input.

## Value

Invisibly NULL.
