# Stateful protected-data policy engine

R6 lifecycle owner for protected datasets, deterministic value indexes,
strategy configuration, tool wrapping, and strict `DescribeData`
metadata. Create one instance per Shiny session or thread; explicitly
share an instance only when those chat threads intentionally share the
same protected data.

`codeagent_client(data_shield = list(shield_*()))` is the declarative
convenience path and creates a private `DataShield` internally. Pass an
explicit `DataShield` instance when data must be registered dynamically
or shared across chats. Instances are intentionally non-cloneable;
create a new object for an independent user/thread boundary.

## Methods

### Public methods

- [`DataShield$new()`](#method-DataShield-initialize)

- [`DataShield$register_data()`](#method-DataShield-register_data)

- [`DataShield$install()`](#method-DataShield-install)

- [`DataShield$describe()`](#method-DataShield-describe)

- [`DataShield$scan_egress()`](#method-DataShield-scan_egress)

- [`DataShield$add_scanner()`](#method-DataShield-add_scanner)

- [`DataShield$clear()`](#method-DataShield-clear)

- [`DataShield$close()`](#method-DataShield-close)

- [`DataShield$coverage()`](#method-DataShield-coverage)

------------------------------------------------------------------------

### `DataShield$new()`

Create a Data Shield.

#### Usage

    DataShield$new(
      max_rows = 0L,
      distributions = "off",
      k_anon = 5L,
      category_max = 20L,
      category_ratio = 0.2,
      strategies = NULL
    )

#### Arguments

- `max_rows`:

  Direct `row_cap` value when `strategies = NULL`: `0` exposes no raw
  tabular line; positive values retain that many leading printed lines.

- `distributions`:

  Direct DescribeData policy. Strict `"off"` only is implemented;
  `"on"`/`"dp"` fail explicitly.

- `k_anon`:

  Minimum category support for exposing a label.

- `category_max`:

  Maximum distinct character values treated as a category.

- `category_ratio`:

  Maximum distinct/non-missing ratio for character categorical
  treatment.

- `strategies`:

  Optional ordered list from
  [`shield_describe()`](https://kaipingyang.github.io/codeagent/reference/shield_describe.md),
  [`shield_egress()`](https://kaipingyang.github.io/codeagent/reference/shield_egress.md),
  and
  [`shield_regex()`](https://kaipingyang.github.io/codeagent/reference/shield_regex.md).
  If supplied, only listed strategies are enabled and list order
  controls egress execution order.

------------------------------------------------------------------------

### `DataShield$register_data()`

Register one protected data.frame.

#### Usage

    DataShield$register_data(
      df,
      name = NULL,
      sensitivity = NULL,
      cols = NULL,
      min_len = 3L,
      min_card = 8L
    )

#### Arguments

- `df`:

  A data.frame retained locally; rows are never emitted by
  `DescribeData`.

- `name`:

  Dataset name used by the model-facing `DescribeData` tool.

- `sensitivity`:

  Optional named overrides: `identifier`, `quasi`, `measure`, or `open`.
  Local heuristics classify unspecified columns.

- `cols`:

  Optional explicit value-match columns. Default: columns classified
  `identifier`/`quasi`.

- `min_len, min_card`:

  Minimum value length and column cardinality for deterministic value
  indexing (reduces low-entropy false positives).

------------------------------------------------------------------------

### `DataShield$install()`

Install/refresh this shield on an ellmer Chat.

#### Usage

    DataShield$install(chat)

------------------------------------------------------------------------

### `DataShield$describe()`

Return strict safe metadata for a registered dataset.

#### Usage

    DataShield$describe(name = NULL)

------------------------------------------------------------------------

### `DataShield$scan_egress()`

Apply the ordered egress strategy pipeline to a tool result.

#### Usage

    DataShield$scan_egress(result)

------------------------------------------------------------------------

### `DataShield$add_scanner()`

Add a custom scanner function to the end of the egress pipeline.

#### Usage

    DataShield$add_scanner(name, fn)

------------------------------------------------------------------------

### `DataShield$clear()`

Remove one dataset, or all datasets when name is NULL.

#### Usage

    DataShield$clear(name = NULL)

------------------------------------------------------------------------

### `DataShield$close()`

Clear sensitive state and close the shield.

#### Usage

    DataShield$close()

------------------------------------------------------------------------

### `DataShield$coverage()`

Summarise non-sensitive runtime coverage.

#### Usage

    DataShield$coverage()

## Examples

``` r
# Easy one-client declaration:
specs <- list(
  shield_describe(k_anon = 5),
  shield_egress(max_rows = 0),
  shield_regex(on_fail = "redact")
)

# Explicit lifecycle for uploaded data / selected shared chats:
shield <- DataShield$new(strategies = specs)
shield$register_data(iris, name = "iris",
  sensitivity = c(Species = "measure"))
shield$coverage()
#> $config
#> $config$max_rows
#> [1] 0
#> 
#> $config$distributions
#> [1] "off"
#> 
#> $config$k_anon
#> [1] 5
#> 
#> $config$category_max
#> [1] 20
#> 
#> $config$category_ratio
#> [1] 0.2
#> 
#> $config$detectors
#> [1] "row_cap"     "value_match"
#> 
#> $config$on_fail
#> [1] "redact"
#> 
#> $config$describe_enabled
#> [1] TRUE
#> 
#> $config$egress_enabled
#> [1] TRUE
#> 
#> 
#> $datasets
#> [1] "iris"
#> 
#> $indexed_values
#> [1] 0
#> 
#> $egress_pipeline
#> [1] "egress" "regex" 
#> 
#> $closed
#> [1] FALSE
#> 
```
