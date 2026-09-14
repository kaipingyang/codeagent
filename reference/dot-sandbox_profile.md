# Build a sandbox profile from settings

Build a sandbox profile from settings

## Usage

``` r
.sandbox_profile(settings = NULL)
```

## Arguments

- settings:

  List or NULL. Reads `settings$sandbox` (a list with optional
  `enabled`, `allow_network`, `keep_env`, `run_r_backend`).

## Value

A normalised profile list. `run_r_backend = "required"` fails closed
because codeagent currently has no OS sandbox backend for arbitrary R;
`"process"` explicitly opts into best-effort callr process isolation.
