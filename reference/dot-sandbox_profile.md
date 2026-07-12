# Build a sandbox profile from settings

Build a sandbox profile from settings

## Usage

``` r
.sandbox_profile(settings = NULL)
```

## Arguments

- settings:

  List or NULL. Reads `settings$sandbox` (a list with optional
  `enabled`, `allow_network`, `keep_env`).

## Value

A normalised profile list: `enabled`, `allow_network`, `keep_env`
(character vector of env var names to preserve).
