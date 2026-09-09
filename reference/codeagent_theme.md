# Build a codeagent application theme

Uses shinychat's official `page_chat_theme()` as the common Bootstrap 5
foundation for both codeagent layouts. The `"glass"` style instead
delegates Liquid Glass material rendering to the optional
[`shinyglass::glass_theme()`](https://ericrayanderson.github.io/shinyglass/reference/glass_theme.html)
package and adds only a thin adapter for shinychat page surfaces. The
returned object can be passed to
[`codeagent_app()`](https://kaipingyang.github.io/codeagent/reference/codeagent_app.md)
or further customized with bslib.

## Usage

``` r
codeagent_theme(style = "default", ...)
```

## Arguments

- style:

  One of `"default"`, `"ios"`, `"aurora"`, `"flatly"`, `"darkly"`, or
  `"glass"`. CLI aliases `"light"`, `"dark"`, and `"glassmorphism"` are
  also accepted. Unknown values fail soft to `"default"`. `"glass"`
  requires the optional `shinyglass` package.

- ...:

  For `style = "glass"`, arguments passed to
  [`shinyglass::glass_theme()`](https://ericrayanderson.github.io/shinyglass/reference/glass_theme.html)
  (for example `preset`, `intensity`, `tint`, and `specular`). For other
  styles, named Bootstrap or shinychat Sass variable overrides passed to
  [`shinychat::page_chat_theme()`](https://posit-dev.github.io/shinychat/r/reference/page_chat_theme.html).
  Overrides take precedence over built-in style defaults.

## Value

A bslib `bs_theme` object.
