# Probe whether `unshare -Urn` (unprivileged user+net namespace) works here.

Runs `unshare -Urn true` once and caches the result. Returns FALSE when
`unshare` is missing, unprivileged userns is disabled, or the probe
errors.

## Usage

``` r
.sandbox_unshare_available()
```
