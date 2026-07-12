# Decide whether RunR code is blocked by the sandbox

RunR executes in-process, so environment scrubbing is impossible.
Instead, when the sandbox is enabled we refuse code that calls network
functions (if `allow_network` is FALSE) or that spawns shells / mutates
the environment (always, since those would sidestep the Bash sandbox).

## Usage

``` r
.sandbox_block_r_code(code, profile)
```

## Arguments

- code:

  Character. The R code to run.

- profile:

  List from
  [`.sandbox_profile()`](https://github.com/kaipingyang/codeagent/reference/dot-sandbox_profile.md).

## Value

NULL if allowed, or a character reason string if blocked.
