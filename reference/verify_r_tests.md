# R package test verification function

Runs `devtools::test()` and returns pass/fail. Use as `verify_fn` in
`codeagent_client()` to automatically re-prompt when tests fail.

## Usage

``` r
verify_r_tests()
```

## Value

A function suitable for `verify_fn`.
