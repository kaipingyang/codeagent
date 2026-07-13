# Compute the environment for a sandboxed command

When the sandbox is enabled, returns a minimal
[`character()`](https://rdrr.io/r/base/character.html) env vector
(NAME=VALUE) limited to `keep_env`. When disabled, returns NULL (inherit
the parent environment, the legacy behaviour).

## Usage

``` r
.sandbox_env(profile)
```

## Arguments

- profile:

  List from
  [`.sandbox_profile()`](https://kaipingyang.github.io/codeagent/reference/dot-sandbox_profile.md).

## Value

Character vector of `NAME=VALUE` strings, or NULL.
