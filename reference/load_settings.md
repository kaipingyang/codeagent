# Load codeagent settings

Merges configuration from all sources in priority order. The trusted
user-level `env` block is applied before the environment-variable layer;
security-sensitive project settings are ignored.

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
