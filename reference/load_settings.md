# Load codeagent settings

Merges configuration from all sources in priority order and applies the
`env` block from settings.json so that environment variables are
available even when running under `Rscript --vanilla`.

## Usage

``` r
load_settings(cwd = getwd())
```

## Arguments

- cwd:

  Character. Working directory (used to locate
  `.codeagent/settings.json` and `CLAUDE.md`). Defaults to
  [`getwd()`](https://rdrr.io/r/base/getwd.html).

## Value

A named list of settings.
