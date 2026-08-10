# Wrap an argv vector to run inside a no-network user+net namespace.

Wrap an argv vector to run inside a no-network user+net namespace.

## Usage

``` r
.sandbox_unshare_wrap(argv, no_network = TRUE)
```

## Arguments

- argv:

  Character vector: the command + args to run (e.g.
  `c("Rscript", "-e", "...")`).

## Value

A character vector prefixed with `unshare -Urn` when available and
requested; otherwise `argv` unchanged.
