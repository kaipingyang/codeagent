# Compute the environment for a sandboxed command

When the sandbox is enabled, returns a minimal named character vector
limited to `keep_env`. `processx` treats a non-NULL `env` as the
complete child environment, unlike base `system2(env=)` which inherits
every unlisted parent variable. When disabled, returns NULL to preserve
legacy inheritance.

## Usage

``` r
.sandbox_env(profile)
```

## Arguments

- profile:

  List from
  [`.sandbox_profile()`](https://kaipingyang.github.io/codeagent/reference/dot-sandbox_profile.md).

## Value

Named character vector, or NULL.
