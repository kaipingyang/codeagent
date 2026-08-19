# Configure strict protected-data metadata

Enable the automatically registered `DescribeData` tool. In the
currently implemented strict mode (`distributions = "off"`), it never
returns rows, histograms, quantiles, means, category counts, or real
free-text examples. `identifier`/`quasi` values are suppressed;
`measure`/`open` columns may show numeric/date min-max and
low-cardinality labels whose support is at least `k_anon` (labels are
shown without counts).

`distributions = "on"`/`"dp"` add a per-category COUNT next to each
k-anonymity-surviving categorical label (`"on"` = real count, `"dp"` =
Laplace-noised count). Numeric/date/logical/free-text columns are
UNCHANGED in all three modes – differential privacy for continuous
statistics (mean/sum) needs a clipping bound that must not be derived
from the private data's own min/max, and that is not yet implemented
(31x scope limit; tracked in
`references/plan/31x-dp-distributions.TODO.md`).

## Usage

``` r
shield_describe(
  distributions = "off",
  k_anon = 5L,
  category_max = 20L,
  category_ratio = 0.2,
  dp_epsilon = .DATA_SHIELD_DP_EPSILON_DEFAULT,
  dp_budget = .DATA_SHIELD_DP_BUDGET_DEFAULT
)
```

## Arguments

- distributions:

  `"off"` (default, safe): no counts, labels only. `"on"`: real
  per-category counts, no privacy protection – explicit opt-in. `"dp"`:
  Laplace-noised per-category counts, spending `dp_epsilon` from that
  dataset's `dp_budget` on every `describe()`/schema-block call that
  exposes them; once a dataset's budget is exhausted it silently
  degrades to `"off"`-style labels-only output for that dataset (no
  error, no raw count, permanent until re-registration).

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

- dp_epsilon:

  Privacy cost (epsilon) charged per describe() call for each
  categorical column exposed under `distributions = "dp"`; split across
  that column's surviving categories. Only meaningful with `"dp"`.

- dp_budget:

  Total per-dataset epsilon budget under `distributions = "dp"`; a
  one-time allowance (no time-window reset). Only meaningful with
  `"dp"`.

## Value

A Data Shield strategy specification.

## Examples

``` r
strict_metadata <- shield_describe(k_anon = 5)
dp_metadata <- shield_describe(distributions = "dp", dp_epsilon = 1, dp_budget = 5)
```
