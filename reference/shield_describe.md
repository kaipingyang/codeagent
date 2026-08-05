# Configure strict protected-data metadata

Enable the automatically registered `DescribeData` tool. In the
currently implemented strict mode (`distributions = "off"`), it never
returns rows, histograms, quantiles, means, category counts, or real
free-text examples. `identifier`/`quasi` values are suppressed;
`measure`/`open` columns may show numeric/date min-max and
low-cardinality labels whose support is at least `k_anon` (labels are
shown without counts).

## Usage

``` r
shield_describe(
  distributions = "off",
  k_anon = 5L,
  category_max = 20L,
  category_ratio = 0.2
)
```

## Arguments

- distributions:

  `"off"` is implemented and is the safe default. `"on"` and `"dp"` are
  accepted as roadmap configuration but DescribeData returns an explicit
  not-implemented error instead of silently weakening privacy.

- k_anon:

  Minimum rows supporting a categorical label before it may be exposed;
  rarer labels become `<rare suppressed>`.

- category_max:

  Maximum distinct values for automatically treating a character column
  as categorical.

- category_ratio:

  Maximum `n_distinct / n_non_missing` ratio for automatic
  character-categorical treatment. Higher-cardinality text is marked
  `free_text` and no examples are returned.

## Value

A Data Shield strategy specification.

## Examples

``` r
strict_metadata <- shield_describe(k_anon = 5)
```
