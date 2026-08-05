# Configure strict protected-data metadata

Configure strict protected-data metadata

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

  Distribution policy. Strict `"off"` is implemented; `"on"` and `"dp"`
  are reserved for later phases.

- k_anon:

  Minimum support before a categorical label may be exposed.

- category_max:

  Maximum distinct values for categorical treatment.

- category_ratio:

  Maximum distinct/row ratio for character categories.

## Value

A Data Shield strategy specification.
