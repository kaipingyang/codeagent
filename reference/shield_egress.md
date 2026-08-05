# Configure tool-result egress protection

Configure tool-result egress protection

## Usage

``` r
shield_egress(
  detectors = c("row_cap", "value_match"),
  max_rows = 0L,
  on_fail = c("redact", "block")
)
```

## Arguments

- detectors:

  Character vector. Implemented detectors are `"row_cap"` and
  `"value_match"`.

- max_rows:

  Rows retained from bulk tabular output (`0` = none).

- on_fail:

  Action label for withheld output. P0/P0.5 support `"redact"` and
  `"block"`; `"ask"` is reserved for a later phase.

## Value

A Data Shield strategy specification.
