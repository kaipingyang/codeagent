# Lint-based verification function

Runs `lintr` on `path` (relative to `cwd`) and reports any lints as a
verification failure, so the agent loop re-enters to fix them. Use as
`verify_fn` in
[`codeagent_client()`](https://kaipingyang.github.io/codeagent/reference/codeagent_client.md)
/
[`agent_loop()`](https://kaipingyang.github.io/codeagent/reference/agent_loop.md),
on its own or combined with
[`verify_r_tests()`](https://kaipingyang.github.io/codeagent/reference/verify_r_tests.md).

## Usage

``` r
verify_r_lints(path = "R")
```

## Arguments

- path:

  Character. File or directory to lint, relative to `cwd` (default
  `"R"`).

## Value

A function suitable for `verify_fn`.
