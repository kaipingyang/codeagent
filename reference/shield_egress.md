# Configure tool-result egress protection

Create the core model-egress stage. Every wrapped tool still executes
locally; this stage controls only what its result may send back to the
LLM.

`row_cap` detects output shaped like a data.frame/tibble or a many-line
rectangular table. With `max_rows = 0` (recommended strict default), it
keeps **zero raw lines** and replaces the output with a shape/withheld
notice. Scalars, ordinary messages, model summaries, plots, and errors
pass through. `value_match` independently withholds high-entropy values
previously indexed by `DataShield$register_data()` (e.g. one subject id
that is too short to trigger the bulk row cap).

## Usage

``` r
shield_egress(
  detectors = c("row_cap", "value_match"),
  max_rows = 0L,
  on_fail = c("redact", "block", "ask"),
  allow_raw_approval = FALSE,
  approval_timeout = 60
)
```

## Arguments

- detectors:

  One or both of `"row_cap"` and `"value_match"`. Default: both, in that
  order.

- max_rows:

  Number of leading printed table lines to retain when `row_cap`
  triggers. `0` retains no raw line; values greater than zero
  deliberately expose that many leading lines and should only be used
  when the caller accepts that disclosure.

- on_fail:

  `"redact"` replaces unsafe output with a withheld notice; `"block"`
  discards it with a blocked notice; `"ask"` pauses before the result
  reaches the LLM and uses the configured egress approval callback.

- allow_raw_approval:

  When `on_fail="ask"`, expose the dangerous `raw_once` choice. Default
  FALSE leaves only redact/block.

- approval_timeout:

  Seconds before an async approval defaults to redact.

## Value

A Data Shield strategy specification.

## Examples

``` r
strict <- shield_egress(max_rows = 0, on_fail = "redact")
no_value_index <- shield_egress(detectors = "row_cap", max_rows = 0)
```
