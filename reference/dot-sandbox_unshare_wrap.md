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

- no_network:

  Logical. Request kernel-level network isolation.

## Value

A character vector prefixed with `unshare -Urn` when available and
requested; otherwise `argv` unchanged. When no-network was requested but
`unshare` is unavailable, the returned vector carries
`attr(x, "network_isolation") = "unavailable"` and a one-time session
warning is emitted – the OS-level boundary has silently degraded to the
command-name blacklist, which is bypassable (kiro round-2 \#12). Callers
should surface this in audit/UI rather than treat `allow_network=FALSE`
as a hard guarantee.
