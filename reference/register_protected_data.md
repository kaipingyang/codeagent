# Register protected data for a session's Data Shield value_match

Index high-entropy values from a data.frame into one **session-scoped**
[`data_shield()`](https://kaipingyang.github.io/codeagent/reference/data_shield.md)
state. All chat threads that share that state will protect the same
uploaded data; other Shiny sessions remain completely isolated.

Supply exactly one of `shield`, `client`, or `chat`. In a Shiny upload
observer the recommended form is
`register_protected_data(df, shield=shield)` where `shield` was created
inside that session's server function.

## Usage

``` r
register_protected_data(
  df,
  name = NULL,
  sensitivity = NULL,
  cols = NULL,
  min_len = 3L,
  min_card = 8L,
  shield = NULL,
  client = NULL,
  chat = NULL
)
```

## Arguments

- df:

  A data.frame (e.g. an uploaded dataset).

- name:

  Character. Dataset name exposed to `DescribeData`; inferred from a
  simple object name or generated when omitted.

- sensitivity:

  Optional named character vector/list assigning columns to
  `identifier`, `quasi`, `measure`, or `open`; local heuristics fill the
  rest.

- cols:

  Optional explicit columns to value-index. By default only columns
  classified `identifier`/`quasi` are indexed.

- min_len, min_card:

  Integer. "Indexable" thresholds: value length and column cardinality.

- shield:

  Optional
  [`data_shield()`](https://kaipingyang.github.io/codeagent/reference/data_shield.md)
  state.

- client:

  Optional `CodeagentClient` that owns a state.

- chat:

  Optional installed ellmer Chat that owns a state.

## Value

Invisibly, the number of values indexed.

## See also

[`data_shield()`](https://kaipingyang.github.io/codeagent/reference/data_shield.md),
[`describe_data_tool()`](https://kaipingyang.github.io/codeagent/reference/describe_data_tool.md),
[`install_data_shield()`](https://kaipingyang.github.io/codeagent/reference/install_data_shield.md),
[`codeagent_client()`](https://kaipingyang.github.io/codeagent/reference/codeagent_client.md)
