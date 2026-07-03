#' @title Interactive Setup Wizard
#' @description `use_codeagent_setup()` guides first-time users through
#'   provider selection, API key configuration, and settings.json creation.
#'   Modelled after `side::setup_client()` by Simon Couch.
#' @name setup
#' @keywords internal
NULL

# ---------------------------------------------------------------------------
# Provider catalogue
# ---------------------------------------------------------------------------

# Each entry: provider name (used in settings.json), ellmer fn, model, env
# vars that signal the provider is configured, and an optional base_url env.
.PROVIDER_CATALOGUE <- list(
  list(
    name        = "openai_compatible",
    label       = "OpenAI-compatible (Databricks / Azure / custom endpoint)",
    fn          = "chat_openai_compatible",
    model       = "your-model-name",
    key_env     = "CODEAGENT_API_KEY",
    base_url    = TRUE,   # requires CODEAGENT_BASE_URL
    detect_envs = "CODEAGENT_BASE_URL"
  ),
  list(
    name        = "anthropic",
    label       = "Anthropic (Claude)",
    fn          = "chat_anthropic",
    model       = "claude-sonnet-4-6",
    key_env     = "ANTHROPIC_API_KEY",
    base_url    = FALSE,
    detect_envs = "ANTHROPIC_API_KEY"
  ),
  list(
    name        = "openai",
    label       = "OpenAI (GPT)",
    fn          = "chat_openai",
    model       = "gpt-4o",
    key_env     = "OPENAI_API_KEY",
    base_url    = FALSE,
    detect_envs = "OPENAI_API_KEY"
  ),
  list(
    name        = "google_gemini",
    label       = "Google Gemini",
    fn          = "chat_google_gemini",
    model       = "gemini-2.5-pro",
    key_env     = "GOOGLE_API_KEY",
    base_url    = FALSE,
    detect_envs = "GOOGLE_API_KEY"
  ),
  list(
    name        = "deepseek",
    label       = "DeepSeek",
    fn          = "chat_deepseek",
    model       = "deepseek-chat",
    key_env     = "DEEPSEEK_API_KEY",
    base_url    = FALSE,
    detect_envs = "DEEPSEEK_API_KEY"
  ),
  list(
    name        = "groq",
    label       = "Groq",
    fn          = "chat_groq",
    model       = "llama-3.3-70b-versatile",
    key_env     = "GROQ_API_KEY",
    base_url    = FALSE,
    detect_envs = "GROQ_API_KEY"
  ),
  list(
    name        = "github",
    label       = "GitHub Copilot",
    fn          = "chat_github",
    model       = "gpt-4o",
    key_env     = "GITHUB_PAT",
    base_url    = FALSE,
    detect_envs = "GITHUB_PAT"
  ),
  list(
    name        = "ollama",
    label       = "Ollama (local)",
    fn          = "chat_ollama",
    model       = "llama3.2",
    key_env     = NULL,
    base_url    = FALSE,
    detect_envs = NULL   # always available if ollama is running
  ),
  list(
    name        = "posit",
    label       = "Posit AI (OAuth device flow)",
    fn          = "chat_posit",
    model       = "claude-sonnet-4-6",
    key_env     = NULL,
    base_url    = FALSE,
    detect_envs = NULL   # auth via OAuth, no env var needed
  )
)

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

#' Interactive setup wizard for codeagent
#'
#' Guides you through choosing a model provider, creates
#' `~/.codeagent/settings.json`, and optionally saves your API key to
#' `~/.Renviron`.  Only works in interactive R sessions.
#'
#' @param scope Character. `"user"` writes to `~/.codeagent/settings.json`;
#'   `"project"` writes to `.codeagent/settings.json` in the current directory.
#' @return Invisibly, the path to the settings file that was written.
#' @export
use_codeagent_setup <- function(scope = c("user", "project")) {
  if (!interactive())
    cli::cli_abort(c(
      "Setup requires an interactive R session.",
      "i" = "Configure manually: {.fn use_codeagent_settings} + edit the file.",
      "i" = "Or call {.fn codeagent_client} with an explicit {.cls Chat} object."
    ))

  scope <- match.arg(scope)

  cli::cli_h1("codeagent setup")
  cli::cli_text("This wizard creates a settings file so {.fn codeagent_client}")
  cli::cli_text("knows which LLM provider and model to use.")
  cat("\n")

  # ---- Step 1: detect + choose provider -----------------------------------
  detected  <- .detect_available_providers()
  catalogue <- .PROVIDER_CATALOGUE
  in_order  <- c(detected, setdiff(catalogue, detected))

  choices <- vapply(in_order, function(p) {
    avail <- p$name %in% vapply(detected, `[[`, character(1), "name")
    if (avail) paste0(p$label, "  [key detected]") else p$label
  }, character(1))
  choices <- c(choices, "Some other provider (enter manually)")

  sel <- utils::menu(choices,
    title = "Which provider/model would you like to use?")
  if (sel == 0) cli::cli_abort("Setup cancelled.")

  # Manual entry
  if (sel == length(choices)) {
    provider <- trimws(readline("Provider name (e.g. openai_compatible): "))
    model    <- trimws(readline("Model name: "))
    base_url <- trimws(readline("Base URL (leave blank if not needed): "))
    key_env  <- trimws(readline("API key env var name (e.g. MY_API_KEY): "))
    info     <- list(name=provider, model=model, key_env=if(nzchar(key_env)) key_env else NULL,
                     base_url=nzchar(base_url), detect_envs=NULL)
  } else {
    info     <- in_order[[sel]]
    model    <- info$model
    base_url <- if (isTRUE(info$base_url))
                  trimws(readline(sprintf("Base URL for %s: ", info$label)))
                else ""
  }

  # ---- Step 2: model name -------------------------------------------------
  cat("\n")
  model_input <- trimws(readline(
    sprintf("Model name [%s]: ", model)))
  if (nzchar(model_input)) model <- model_input

  # ---- Step 3: API key -----------------------------------------------------
  key_env  <- info$key_env %||% NULL
  key_val  <- if (!is.null(key_env)) Sys.getenv(key_env, "") else ""
  save_key <- FALSE

  if (!is.null(key_env) && !nzchar(key_val)) {
    cat("\n")
    cli::cli_alert_warning("{.envvar {key_env}} is not set.")
    key_input <- trimws(readline(
      sprintf("Paste your %s API key (leave blank to skip): ", info$label)))
    if (nzchar(key_input)) {
      Sys.setenv(setNames(key_input, key_env))
      key_val  <- key_input
      save_key <- TRUE
    }
  }

  # ---- Step 4: build settings + write file --------------------------------
  cat("\n")
  env_block <- list()
  if (nzchar(base_url)) env_block[["CODEAGENT_BASE_URL"]] <- base_url
  if (!is.null(key_env)) env_block[[key_env]] <- if (nzchar(key_val)) key_val else "<your-key>"

  new_settings <- list(
    provider = info$name,
    model    = model
  )
  if (length(env_block)) new_settings[["env"]] <- env_block

  # Merge with existing file if present.
  dest_dir <- if (identical(scope, "user")) .get_codeagent_dir()
              else file.path(getwd(), ".codeagent")
  dir.create(dest_dir, showWarnings = FALSE, recursive = TRUE)
  dest <- file.path(dest_dir, "settings.json")

  if (file.exists(dest)) {
    existing <- tryCatch(jsonlite::fromJSON(dest, simplifyVector=FALSE),
                         error = function(e) list())
    new_settings <- .merge_settings(existing, new_settings)
  }
  writeLines(jsonlite::toJSON(new_settings, auto_unbox=TRUE, pretty=TRUE), dest)
  cli::cli_alert_success("Settings written to {.file {dest}}")

  # ---- Step 5: persist API key ------------------------------------------------
  if (save_key && !is.null(key_env) && nzchar(key_val)) {
    keyring_ok <- .keyring_available()
    persist_choices <- c(
      "Just for this R session (already active)",
      if (keyring_ok) "OS keyring (secure, no plaintext on disk)" else NULL,
      "Save to ~/.Renviron (plaintext, persists across sessions)"
    )
    persist_sel <- utils::menu(persist_choices,
      title = sprintf("Store %s API key...", info$label))
    if (persist_sel == 0) {
      # cancelled — nothing
    } else if (keyring_ok && persist_sel == 2) {
      .keyring_store_key(key_env, key_val, backend = "keyring")
    } else if (persist_sel == length(persist_choices)) {
      .append_renviron(key_env, key_val)
    }
  }

  # ---- Step 6: summary -----------------------------------------------------
  cat("\n")
  cli::cli_h2("Configuration summary")
  cli::cli_bullets(c(
    "*" = "Provider: {.val {info$name}}",
    "*" = "Model:    {.val {model}}",
    "*" = "Settings: {.file {dest}}"
  ))
  cli::cli_text("\nRun {.code codeagent_client()} to start using codeagent.")
  if (save_key)
    cli::cli_text("Restart R (or run {.code readRenviron('~/.Renviron')}) to reload the key.")

  invisible(dest)
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Detect which providers are likely configured (env vars present).
.detect_available_providers <- function() {
  Filter(function(p) {
    envs <- p$detect_envs
    if (is.null(envs)) return(TRUE)   # local providers like ollama always shown
    any(nzchar(Sys.getenv(envs, "")))
  }, .PROVIDER_CATALOGUE)
}

# Append KEY=value to ~/.Renviron without duplicating.
.append_renviron <- function(key, value) {
  renv_path <- path.expand("~/.Renviron")
  existing  <- if (file.exists(renv_path)) readLines(renv_path, warn=FALSE)
               else character(0)
  if (any(grepl(paste0("^", key, "="), existing))) {
    cli::cli_alert_warning("{.envvar {key}} already in {.file {renv_path}}. Not overwriting.")
    return(invisible(NULL))
  }
  line <- sprintf('%s="%s"', key, value)
  writeLines(c(existing, line), renv_path)
  readRenviron(renv_path)
  cli::cli_alert_success("Added {.envvar {key}} to {.file {renv_path}}")
  invisible(NULL)
}
