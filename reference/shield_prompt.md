# Data Shield policy for what the user types

How the input gate treats protected content in a user's message before
it reaches the model. `"ask"`: subject identifiers block the message
(the chat says which columns, never the values); a pasted table of
numbers (at least five lines with two or more columns and a digit) asks
the user in the question card before it is sent; other protected values
are redacted and the chat says which columns. `"redact"` (the default
without this strategy) replaces protected values and goes on; `"block"`
stops the message. A client's `settings$data_shield_prompt_on_fail`
still wins when set.

## Usage

``` r
shield_prompt(on_fail = c("ask", "redact", "block"))
```

## Arguments

- on_fail:

  `"ask"`, `"redact"` or `"block"`.

## Value

A Data Shield strategy specification.

## See also

[`shield_egress()`](https://kaipingyang.github.io/codeagent/reference/shield_egress.md)

## Examples

``` r
shield <- DataShield$new(strategies = list(shield_egress(), shield_prompt("ask")))
```
