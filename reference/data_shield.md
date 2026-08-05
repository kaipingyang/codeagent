# Data Shield — pluggable strict data-safety valve (P0 core)

Opt-in guard that stops raw row-level data from reaching the LLM via the
two inbound edges: (1) prompt-side auto-injection (ambient context) and
(2) tool results. Off by default (`data_shield = NULL`).

This file contains the P0 core: a content-agnostic, shape-based **egress
row-cap** for tool results (edge 2). It does NOT inspect code or block
`print`; it looks only at the *shape* of a tool's returned text and
truncates output that has the signature of a bulk row-level data dump,
passing scalars, messages, model summaries, plots and errors through
untouched.

Create the mutable state shared by all codeagent clients / chat threads
in one user session. The protected-value index lives here (never
package-global), so separate Shiny sessions cannot see or influence each
other's values.

Pass the returned object as `data_shield = shield` to every
[`codeagent_client()`](https://kaipingyang.github.io/codeagent/reference/codeagent_client.md)
created for that user session, then register uploaded data with
`register_protected_data(df, shield = shield)`.

## Usage

``` r
data_shield(
  max_rows = 0L,
  distributions = "off",
  k_anon = 5L,
  category_max = 20L,
  category_ratio = 0.2
)
```

## Arguments

- max_rows:

  Integer. Rows to retain from bulk tabular tool output (`0` means shape
  summary only).

- distributions:

  Distribution policy. P1 currently implements strict `"off"`; `"on"`
  and `"dp"` are reserved for later phases.

- k_anon:

  Integer. Minimum support required before a categorical label may be
  exposed (default 5).

- category_max:

  Integer. Maximum distinct values for automatic categorical treatment.

- category_ratio:

  Numeric. Maximum distinct/row ratio for a character column to be
  treated as categorical.

## Value

A mutable `DataShieldState` environment.
