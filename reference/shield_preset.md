# Ready-made Data Shield strategy combinations

Three combination templates lifted verbatim from the "ready-to-use
combination templates" section of
[`vignette("data-shield")`](https://kaipingyang.github.io/codeagent/articles/data-shield.md),
as callable functions instead of copy-pasted code. Each returns a
[`list()`](https://rdrr.io/r/base/list.html) of strategy specifications
suitable for `codeagent_client(data_shield = ...)` or
`DataShield$new(strategies = ...)`. None of them register
`shield_reviewer` with a live client_factory except
`shield_preset_clinical()`, which uses `CODEAGENT_FAST_MODEL` like the
rest of the package.

- `shield_preset_strict()`: compliance/audit demos. Fails closed
  (`on_fail = "block"` everywhere) and strict k-anonymity.

- `shield_preset_balanced()`: everyday development, low friction.
  Redacts instead of blocking; no ingress scanning or describe metadata.

- `shield_preset_clinical()`: adds the semantic
  [`shield_reviewer()`](https://kaipingyang.github.io/codeagent/reference/shield_reviewer.md)
  rail on top of strict k-anonymity, with `"ask"` (not `"block"`) fail
  policy.

These are starting points, not a certification – read the vignette's
"Combination safety" matrix before deploying any of them as-is.

## Usage

``` r
shield_preset_strict()

shield_preset_balanced()

shield_preset_clinical()
```

## Value

A [`list()`](https://rdrr.io/r/base/list.html) of Data Shield strategy
specifications.

## Examples

``` r
client <- codeagent_client(chat, data_shield = shield_preset_strict())
#> Error: object 'chat' not found
client <- codeagent_client(chat, data_shield = shield_preset_balanced())
#> Error: object 'chat' not found
```
