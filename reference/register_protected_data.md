# Register protected data for the Data Shield value_match

Index the (high-entropy) values of a data.frame so the Data Shield
egress guard withholds them if they surface in a tool result (e.g. a
tool that prints one subject's name or id – something the shape-based
row-cap lets through). Only long, high-cardinality, non-small-integer
values are indexed; common / low-cardinality / small-integer values are
skipped to avoid false positives (those belong to the describe layer,
not value_match).

Effects are process-global for the session (per-session isolation is a
planned follow-up). Call once per protected dataset, then
[`install_data_shield()`](https://kaipingyang.github.io/codeagent/reference/install_data_shield.md)
(or `codeagent_client(data_shield=)`).

## Usage

``` r
register_protected_data(df, cols = NULL, min_len = 3L, min_card = 8L)
```

## Arguments

- df:

  A data.frame (e.g. an uploaded dataset).

- cols:

  Character. Columns to index (default: all).

- min_len, min_card:

  Integer. "Indexable" thresholds: value length and column cardinality.

## Value

Invisibly, the number of values indexed.

## See also

[`install_data_shield()`](https://kaipingyang.github.io/codeagent/reference/install_data_shield.md),
[`codeagent_client()`](https://kaipingyang.github.io/codeagent/reference/codeagent_client.md)
