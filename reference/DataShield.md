# Stateful protected-data policy engine

R6 lifecycle owner for protected datasets, deterministic value indexes,
strategy configuration, tool wrapping, and strict `DescribeData`
metadata. Create one instance per Shiny session or thread; explicitly
share an instance only when those chat threads intentionally share the
same protected data.

`codeagent_client(data_shield = list(shield_*()))` is the declarative
convenience path and creates a private `DataShield` internally. Pass an
explicit `DataShield` instance when data must be registered dynamically
or shared across chats.

## Methods

### Public methods

- [`DataShield$new()`](#method-DataShield-initialize)

- [`DataShield$register_data()`](#method-DataShield-register_data)

- [`DataShield$install()`](#method-DataShield-install)

- [`DataShield$describe()`](#method-DataShield-describe)

- [`DataShield$scan_egress()`](#method-DataShield-scan_egress)

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

- `max_rows, k_anon, category_max, category_ratio`:

  Direct defaults used when `strategies` is NULL.

- `distributions`:

  Direct strict metadata policy.

- `strategies`:

  Optional list from
  [`shield_describe()`](https://kaipingyang.github.io/codeagent/reference/shield_describe.md)
  and
  [`shield_egress()`](https://kaipingyang.github.io/codeagent/reference/shield_egress.md).

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

  A data.frame.

- `name`:

  Dataset name used by `DescribeData`.

- `sensitivity`:

  Optional named identifier/quasi/measure/open overrides.

- `cols`:

  Optional explicit columns to value-index.

- `min_len, min_card`:

  High-entropy index thresholds.

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

Apply the egress pipeline to a tool result.

#### Usage

    DataShield$scan_egress(result)

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
