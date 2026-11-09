# Permission mode switch for a host app

A small radio group the user switches the session's permission mode
with, for example between asking before every change and running without
asking. Pass the same `modes` to
[`codeagent_server()`](https://kaipingyang.github.io/codeagent/reference/codeagent_server.md).
Only one per page.

## Usage

``` r
codeagent_mode_ui(
  modes = c(`Ask before changes` = "default", `Run without asking` = "bypass"),
  selected = NULL,
  label = NULL
)
```

## Arguments

- modes:

  Named character vector: label -\> mode. Modes: `"default"` (ask before
  tools that change something), `"accept_edits"` (file edits run, other
  changes ask), `"bypass"` (nothing asks), `"dont_ask"` (what would ask
  is refused).

- selected:

  The mode selected at start (default: the first).

- label:

  Optional label shown before the choices.

## Value

A Shiny tag.

## See also

[`codeagent_server()`](https://kaipingyang.github.io/codeagent/reference/codeagent_server.md)
