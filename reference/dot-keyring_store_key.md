# Store an API key, preferring the OS credential store

Attempts to save `key_value` under `key_name` (service = "codeagent")
via `keyring`. If keyring is unavailable (no daemon, no package), falls
back to appending `KEY=value` to `~/.Renviron` via `.append_renviron()`.

## Usage

``` r
.keyring_store_key(
  key_name,
  key_value,
  backend = c("auto", "keyring", "renviron")
)
```

## Arguments

- key_name:

  Character. Environment variable name (e.g. `"OPENAI_API_KEY"`).

- key_value:

  Character. The secret value.

- backend:

  Character. `"auto"` (default) tries keyring then .Renviron;
  `"keyring"` forces keyring (errors if unavailable); `"renviron"`
  forces .Renviron.

## Value

Invisibly `"keyring"` or `"renviron"` depending on which backend was
used.
