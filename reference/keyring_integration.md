# Keyring Integration (Optional)

Optional helpers for storing API keys in the OS credential store via the
`keyring` package. When keyring is unavailable or the secret service
daemon is not running, all functions fall back gracefully to
`~/.Renviron` (the existing behaviour).

Call hierarchy:

  - `keyring_store_key()` – save a key (keyring preferred, .Renviron
    fallback)

  - `keyring_get_key()` – retrieve a key (keyring -\> env var -\> "")

  - `.keyring_available()` – runtime probe; cached per session
