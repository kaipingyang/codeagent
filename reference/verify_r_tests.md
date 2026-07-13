# R package test verification function

Runs
[`devtools::test()`](https://devtools.r-lib.org/reference/test.html) and
returns pass/fail. Use as `verify_fn` in
[`codeagent_client()`](https://kaipingyang.github.io/codeagent/reference/codeagent_client.md)
to automatically re-prompt when tests fail.

## Usage

``` r
verify_r_tests()
```

## Value

A function suitable for `verify_fn`.
