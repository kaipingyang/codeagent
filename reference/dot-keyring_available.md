# Check whether keyring is usable in this R session

Probes the keyring backend once (per session) and caches the result.
Returns `FALSE` on headless/server environments where the secret-service
daemon is absent, so callers can fall back to `~/.Renviron`.

## Usage

``` r
.keyring_available()
```

## Value

`TRUE` if keyring is installed and the backend responds.
