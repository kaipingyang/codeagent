#' @title Keyring Integration (Optional)
#' @description Optional helpers for storing API keys in the OS credential
#'   store via the `keyring` package. When keyring is unavailable or the
#'   secret service daemon is not running, all functions fall back gracefully
#'   to `~/.Renviron` (the existing behaviour).
#'
#'   Call hierarchy:
#'   - `keyring_store_key()` -- save a key (keyring preferred, .Renviron fallback)
#'   - `keyring_get_key()` -- retrieve a key (keyring -> env var -> "")
#'   - `.keyring_available()` -- runtime probe; cached per session
#' @name keyring_integration
#' @keywords internal
NULL

# Session-level availability cache to avoid repeated D-Bus probes.
.keyring_avail_cache <- local({
  val <- NULL
  list(
    get = function() val,
    set = function(x) { val <<- x; x }
  )
})

#' Check whether keyring is usable in this R session
#'
#' Probes the keyring backend once (per session) and caches the result.
#' Returns `FALSE` on headless/server environments where the secret-service
#' daemon is absent, so callers can fall back to `~/.Renviron`.
#'
#' @return `TRUE` if keyring is installed and the backend responds.
#' @keywords internal
.keyring_available <- function() {
  cached <- .keyring_avail_cache$get()
  if (!is.null(cached)) return(cached)

  ok <- requireNamespace("keyring", quietly = TRUE) &&
    tryCatch({
      keyring::keyring_list()
      TRUE
    }, error = function(e) FALSE)

  .keyring_avail_cache$set(ok)
}

#' Store an API key, preferring the OS credential store
#'
#' Attempts to save `key_value` under `key_name` (service = "codeagent")
#' via `keyring`. If keyring is unavailable (no daemon, no package), falls
#' back to appending `KEY=value` to `~/.Renviron` via [.append_renviron()].
#'
#' @param key_name Character. Environment variable name (e.g. `"OPENAI_API_KEY"`).
#' @param key_value Character. The secret value.
#' @param backend Character. `"auto"` (default) tries keyring then .Renviron;
#'   `"keyring"` forces keyring (errors if unavailable);
#'   `"renviron"` forces .Renviron.
#' @return Invisibly `"keyring"` or `"renviron"` depending on which backend
#'   was used.
#' @keywords internal
.keyring_store_key <- function(key_name, key_value,
                                backend = c("auto", "keyring", "renviron")) {
  backend <- match.arg(backend)

  use_keyring <- switch(backend,
    auto    = .keyring_available(),
    keyring = {
      if (!.keyring_available())
        cli::cli_abort(c(
          "keyring backend requested but not available.",
          "i" = "Install keyring and ensure a secret-service daemon is running.",
          "i" = "On servers, use {.code options(keyring_backend='file')} for ",
          "i" = "an encrypted file backend."
        ))
      TRUE
    },
    renviron = FALSE
  )

  if (use_keyring) {
    keyring::key_set_with_value(
      service  = "codeagent",
      username = key_name,
      password = key_value
    )
    cli::cli_alert_success(
      "Saved {.envvar {key_name}} to OS keyring (service = {.val codeagent}).")
    # Also set in current session so tools can find it immediately.
    do.call(Sys.setenv, setNames(list(key_value), key_name))
    return(invisible("keyring"))
  }

  # Fallback: ~/.Renviron
  .append_renviron(key_name, key_value)
  invisible("renviron")
}

#' Retrieve an API key from keyring or the environment
#'
#' Looks up `key_name` in order:
#' 1. OS keyring (service = "codeagent"), if available
#' 2. Environment variable `key_name`
#' 3. Returns `""` (not found)
#'
#' @param key_name Character. Environment variable / keyring username.
#' @return The key value as a string, or `""` if not found.
#' @keywords internal
.keyring_get_key <- function(key_name) {
  if (.keyring_available()) {
    val <- tryCatch(
      keyring::key_get(service = "codeagent", username = key_name),
      error = function(e) NULL
    )
    if (!is.null(val) && nzchar(val)) return(val)
  }
  Sys.getenv(key_name, "")
}

#' Delete a key from the OS keyring
#'
#' No-op (with a warning) if the key does not exist or keyring is unavailable.
#'
#' @param key_name Character. Environment variable / keyring username.
#' @return Invisibly `TRUE` if deleted, `FALSE` if not found or unavailable.
#' @keywords internal
.keyring_delete_key <- function(key_name) {
  if (!.keyring_available()) {
    cli::cli_alert_warning("keyring not available; cannot delete {.envvar {key_name}}.")
    return(invisible(FALSE))
  }
  tryCatch({
    keyring::key_delete(service = "codeagent", username = key_name)
    cli::cli_alert_success("Deleted {.envvar {key_name}} from OS keyring.")
    invisible(TRUE)
  }, error = function(e) {
    cli::cli_alert_warning(
      "Could not delete {.envvar {key_name}} from keyring: {conditionMessage(e)}")
    invisible(FALSE)
  })
}
