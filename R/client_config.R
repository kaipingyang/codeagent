#' @title Client Configuration
#' @description Read multi-client configuration from `codeagent.md` or
#'   `.codeagent/config.md` files, mirroring btw's `btw.md` support.
#' @name client_config
#' @keywords internal
NULL

# ---------------------------------------------------------------------------
# codeagent.md format
# ---------------------------------------------------------------------------
#
# YAML frontmatter:
#
#   client: openai/gpt-5.4              # single client
#   # OR
#   client:                             # multiple with aliases
#     gpt41:   openai/gsds-gpt41
#     gpt55:   openai/gsds-gpt-55
#     deepseek: openai/deepseek-r1
#
#   btw_groups:                         # btw tool groups to enable
#     - docs
#     - git
#     - pkg
#
#   permission_mode: bypass
#   max_turns: 50
#
# Body (after ---) is injected into the system prompt.

# Config file search paths (project-local, then user-global)
.CODEAGENT_CONFIG_FILES <- c(
  ".codeagent/config.md",
  "codeagent.md"
)

.CODEAGENT_USER_CONFIG <- file.path("~", ".codeagent", "config.md")

# ---------------------------------------------------------------------------
# Read and parse codeagent.md
# ---------------------------------------------------------------------------

#' Read codeagent configuration from codeagent.md / .codeagent/config.md
#'
#' Searches the project directory and user home for a configuration file.
#' Returns a named list with fields: `client_spec`, `btw_groups`,
#' `permission_mode`, `max_turns`, `system_prompt`.
#'
#' @param cwd Character. Project directory to search.
#' @return Named list of config fields, or empty list if no file found.
#' @keywords internal
.read_codeagent_config <- function(cwd = getwd()) {
  # Search for config file
  path <- NULL
  for (f in .CODEAGENT_CONFIG_FILES) {
    candidate <- file.path(cwd, f)
    if (file.exists(candidate)) { path <- candidate; break }
  }
  # User-level fallback
  user_cfg <- path.expand(.CODEAGENT_USER_CONFIG)
  if (is.null(path) && file.exists(user_cfg)) path <- user_cfg
  if (is.null(path)) return(list())

  lines <- tryCatch(readLines(path, warn = FALSE), error = function(e) character(0))
  if (length(lines) < 2L || !identical(trimws(lines[1L]), "---")) return(list())

  # Find end of frontmatter
  end_idx <- which(trimws(lines[-1L]) == "---")[1L] + 1L
  if (is.na(end_idx)) return(list())

  fm_text <- paste(lines[2L:(end_idx - 1L)], collapse = "\n")
  body    <- if (end_idx < length(lines))
    paste(lines[(end_idx + 1L):length(lines)], collapse = "\n")
  else ""

  # Parse YAML frontmatter via yaml package if available
  fm <- tryCatch({
    if (requireNamespace("yaml", quietly = TRUE))
      yaml::yaml.load(fm_text)
    else
      .simple_yaml_parse(fm_text)
  }, error = function(e) list())

  list(
    client_spec     = fm[["client"]] %||% NULL,
    btw_groups      = fm[["btw_groups"]] %||% NULL,
    permission_mode = fm[["permission_mode"]] %||% NULL,
    max_turns       = if (!is.null(fm[["max_turns"]])) as.integer(fm[["max_turns"]]) else NULL,
    system_prompt   = if (nzchar(trimws(body))) trimws(body) else NULL,
    path            = path
  )
}

# Simple key: value / key:\n  - item YAML parser (no dependency on yaml pkg)
.simple_yaml_parse <- function(text) {
  lines  <- strsplit(text, "\n")[[1L]]
  result <- list()
  i <- 1L
  while (i <= length(lines)) {
    ln <- lines[[i]]
    # list items under current key
    if (grepl("^  - ", ln)) { i <- i + 1L; next }
    m <- regexec("^([a-zA-Z_-]+):\\s*(.*)", ln)
    caps <- regmatches(ln, m)[[1L]]
    if (length(caps) == 3L) {
      key <- caps[2L]; val <- trimws(caps[3L])
      if (!nzchar(val)) {
        # Multi-line: collect "  - item" lines
        items <- character(0)
        j <- i + 1L
        while (j <= length(lines) && grepl("^  [-: ]", lines[[j]])) {
          item_m <- regexec("^\\s+-\\s+(.*)", lines[[j]])
          item_c <- regmatches(lines[[j]], item_m)[[1L]]
          if (length(item_c) == 2L) items <- c(items, trimws(item_c[2L]))
          # key: value alias format
          alias_m <- regexec("^\\s+([a-zA-Z_-]+):\\s+(.*)", lines[[j]])
          alias_c <- regmatches(lines[[j]], alias_m)[[1L]]
          if (length(alias_c) == 3L) {
            if (!is.list(result[[key]])) result[[key]] <- list()
            result[[key]][[alias_c[2L]]] <- trimws(alias_c[3L])
          }
          j <- j + 1L
        }
        if (length(items) > 0L && !is.list(result[[key]]))
          result[[key]] <- items
        i <- j
      } else {
        result[[key]] <- val
      }
    } else {
      i <- i + 1L
    }
  }
  result
}

# ---------------------------------------------------------------------------
# Parse client spec to codeagent_client() arguments
# ---------------------------------------------------------------------------

#' Parse a client spec string ("provider/model") into chat factory args
#'
#' Supports:
#' - `"openai/model-name"` -> `chat_openai_compatible()` using `CODEAGENT_BASE_URL`
#' - `"anthropic/model-name"` -> `chat_anthropic(model = "model-name")`
#' - `"alias"` -> looked up in `aliases` named list
#'
#' @param spec Character. Client spec string or alias key.
#' @param aliases Named list. Alias -> spec mapping.
#' @param cwd Character. Working directory (for settings).
#' @return An `ellmer::Chat` object.
#' @keywords internal
.parse_client_spec <- function(spec, aliases = list(), cwd = getwd()) {
  # Resolve alias
  if (!is.null(aliases[[spec]])) spec <- aliases[[spec]]

  # Resolve tier alias (sonnet/opus/haiku) via env vars set by settings.json env block.
  # Mirrors Claude Code's ANTHROPIC_DEFAULT_SONNET_MODEL / ANTHROPIC_SMALL_FAST_MODEL.
  tier_map <- .build_tier_models()
  if (!is.null(tier_map[[spec]])) spec <- tier_map[[spec]]

  # "anthropic/model"
  if (grepl("^anthropic/", spec)) {
    model <- sub("^anthropic/", "", spec)
    return(ellmer::chat_anthropic(model = model))
  }

  # "openai/model" -- use CODEAGENT_BASE_URL
  if (grepl("^openai/", spec)) {
    model   <- sub("^openai/", "", spec)
    base_url <- Sys.getenv("CODEAGENT_BASE_URL", "")
    if (nzchar(base_url)) {
      return(ellmer::chat_openai_compatible(
        base_url    = base_url,
        model       = model,
        credentials = function() Sys.getenv("CODEAGENT_API_KEY")
      ))
    }
    # Fall through to anthropic if no base_url
  }

  # "ollama/model"
  if (grepl("^ollama/", spec)) {
    model <- sub("^ollama/", "", spec)
    return(tryCatch(
      ellmer::chat_ollama(model = model),
      error = function(e) stop("ollama not available: ", conditionMessage(e))
    ))
  }

  # Plain model name -- use settings auto-detect
  settings <- load_settings(cwd)
  settings$model <- spec
  .make_chat(settings, cwd)
}

# ---------------------------------------------------------------------------
# Public API: codeagent_client_config()
# ---------------------------------------------------------------------------

#' Create a codeagent.md configuration file
#'
#' Copies the codeagent.md template to the project root (or `.codeagent/config.md`).
#'
#' @param path Character. Destination path. Defaults to `"codeagent.md"`.
#' @param open Logical. Open the file after creation (requires rstudioapi).
#' @return Invisible character. Path to created file.
#' @export
use_codeagent_md <- function(path = "codeagent.md", open = interactive()) {
  template <- system.file("templates", "codeagent.md", package = "codeagent")
  if (!nzchar(template) || !file.exists(template))
    cli::cli_abort("codeagent.md template not found in the codeagent package.")
  if (file.exists(path))
    cli::cli_abort("{.path {path}} already exists.")
  file.copy(template, path)
  cli::cli_alert_success("Created {.path {path}}")
  if (open && requireNamespace("rstudioapi", quietly = TRUE) &&
      rstudioapi::hasFun("navigateToFile"))
    rstudioapi::navigateToFile(path)
  invisible(path)
}
#'
#' Reads `codeagent.md` or `.codeagent/config.md` in the project directory
#' and constructs a [codeagent_client()] from the declared settings.
#' Supports multi-client aliases (pick interactively or by name).
#'
#' @param alias Character or NULL. Select a specific alias from `client:`
#'   section. NULL uses the first/only defined client.
#' @param cwd Character. Project directory.
#' @param ... Additional arguments passed to [codeagent_client()].
#' @return A `CodeagentClient` object, or NULL if no config file found.
#' @export
codeagent_client_config <- function(alias = NULL, cwd = getwd(), ...) {
  cfg <- .read_codeagent_config(cwd)
  if (length(cfg) == 0L) {
    message("[codeagent] No codeagent.md or .codeagent/config.md found. ",
            "Using environment variables.")
    return(codeagent_client(cwd = cwd, ...))
  }

  # Resolve client spec
  chat <- NULL
  if (!is.null(cfg$client_spec)) {
    spec <- cfg$client_spec
    if (is.list(spec)) {
      # Aliases map
      aliases <- spec
      if (!is.null(alias)) {
        if (!alias %in% names(aliases))
          stop("Alias '", alias, "' not found. Available: ",
               paste(names(aliases), collapse = ", "), call. = FALSE)
        chat <- .parse_client_spec(aliases[[alias]], cwd = cwd)
      } else if (interactive()) {
        choice <- utils::menu(names(aliases), title = "Select client:")
        if (choice == 0L) stop("Aborted.", call. = FALSE)
        chat <- .parse_client_spec(aliases[[names(aliases)[choice]]], cwd = cwd)
      } else {
        chat <- .parse_client_spec(aliases[[1L]], aliases = list(), cwd = cwd)
      }
    } else {
      chat <- .parse_client_spec(as.character(spec), cwd = cwd)
    }
  }

  # Build client with config overrides
  args <- list(
    chat            = chat,
    cwd             = cwd,
    permission_mode = cfg$permission_mode %||% "default",
    max_turns       = cfg$max_turns       %||% 100L,
    btw_groups      = cfg$btw_groups
  )
  args <- utils::modifyList(args, list(...))

  client <- do.call(codeagent_client, args)

  # Inject config body into system prompt if present
  if (!is.null(cfg$system_prompt) && nzchar(cfg$system_prompt)) {
    current_sp <- tryCatch(client$chat$get_system_prompt() %||% "",
                           error = function(e) "")
    new_sp <- if (nzchar(current_sp))
      paste0(current_sp, "\n\n---\n\n", cfg$system_prompt)
    else
      cfg$system_prompt
    tryCatch(client$chat$set_system_prompt(new_sp), error = function(e) NULL)
  }

  client
}
