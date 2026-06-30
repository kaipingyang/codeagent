#' @title Settings System
#' @description Configuration loading for codeagent.
#'   Priority (highest to lowest): environment variables >
#'   `~/.codeagent/settings.json` > `.codeagent/settings.json` > CLAUDE.md.
#' @name settings
#' @keywords internal
NULL

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------

.CODEAGENT_DEFAULTS <- list(
  model           = "claude-sonnet-4-6",
  permission_mode = "default",
  max_turns       = 100L,
  model_limit     = 200000L,   # context window tokens
  max_output_tokens = 8192L,
  thinking        = FALSE,
  stream          = TRUE,
  base_url        = NULL,      # non-NULL → OpenAI-compatible endpoint
  api_key_env     = NULL       # env var name for the API key (default auto-detect)
)

# ---------------------------------------------------------------------------
# Main entry point
# ---------------------------------------------------------------------------

#' Load codeagent settings
#'
#' Merges configuration from all sources according to priority order.
#'
#' @param cwd Character. Working directory (used to locate `.codeagent/settings.json`
#'   and `CLAUDE.md`). Defaults to `getwd()`.
#' @return A named list of settings.
#' @export
load_settings <- function(cwd = getwd()) {
  settings <- .CODEAGENT_DEFAULTS

  # Layer 3 & 2: JSON files (project overrides user)
  user_json    <- file.path(.get_codeagent_dir(), "settings.json")
  project_json <- file.path(cwd, ".codeagent", "settings.json")

  for (json_path in c(user_json, project_json)) {
    if (file.exists(json_path)) {
      overrides <- tryCatch(
        jsonlite::fromJSON(json_path, simplifyVector = TRUE),
        error = function(e) {
          warning("Failed to parse ", json_path, ": ", conditionMessage(e),
                  call. = FALSE)
          list()
        }
      )
      settings <- .merge_settings(settings, overrides)
    }
  }

  # Layer 1: Environment variables (highest priority)
  env_model <- Sys.getenv("CODEAGENT_MODEL", "")
  if (nzchar(env_model)) settings$model <- env_model

  env_perm <- Sys.getenv("CODEAGENT_PERMISSION_MODE", "")
  if (nzchar(env_perm)) settings$permission_mode <- env_perm

  env_turns <- Sys.getenv("CODEAGENT_MAX_TURNS", "")
  if (nzchar(env_turns)) settings$max_turns <- as.integer(env_turns)

  env_limit <- Sys.getenv("CODEAGENT_MODEL_LIMIT", "")
  if (nzchar(env_limit)) settings$model_limit <- as.integer(env_limit)

  env_base_url <- Sys.getenv("CODEAGENT_BASE_URL", "")
  if (nzchar(env_base_url)) settings$base_url <- env_base_url

  # CLAUDE.md (loaded as context, not merged as settings)
  settings$claude_md <- .load_claude_md(cwd)

  settings
}

# ---------------------------------------------------------------------------
# CLAUDE.md loading
# ---------------------------------------------------------------------------

#' Load CLAUDE.md from cwd or parent directories
#'
#' Walks up the directory tree (max 5 levels) looking for a `CLAUDE.md` file.
#'
#' @param cwd Character. Starting directory.
#' @return Character(1) with file contents, or NULL if not found.
#' @keywords internal
.load_claude_md <- function(cwd) {
  path <- cwd
  for (i in seq_len(5L)) {
    candidate <- file.path(path, "CLAUDE.md")
    if (file.exists(candidate)) {
      lines <- tryCatch(readLines(candidate, warn = FALSE),
                        error = function(e) NULL)
      if (!is.null(lines)) return(paste(lines, collapse = "\n"))
    }
    parent <- dirname(path)
    if (parent == path) break
    path <- parent
  }
  NULL
}

# ---------------------------------------------------------------------------
# Settings helpers
# ---------------------------------------------------------------------------

# Deep-merge two lists (right takes precedence)
.merge_settings <- function(base, overrides) {
  for (key in names(overrides)) {
    val <- overrides[[key]]
    if (is.list(val) && is.list(base[[key]])) {
      base[[key]] <- .merge_settings(base[[key]], val)
    } else {
      base[[key]] <- val
    }
  }
  base
}

#' Save user settings to ~/.codeagent/settings.json
#'
#' @param settings Named list of settings to save.
#' @return Invisible NULL.
#' @export
save_user_settings <- function(settings) {
  dir <- .get_codeagent_dir()
  dir.create(dir, showWarnings = FALSE, recursive = TRUE)
  path <- file.path(dir, "settings.json")
  # Read existing, merge, write back
  existing <- if (file.exists(path)) {
    tryCatch(jsonlite::fromJSON(path, simplifyVector = FALSE), error = function(e) list())
  } else list()
  merged <- .merge_settings(existing, settings)
  writeLines(jsonlite::toJSON(merged, auto_unbox = TRUE, pretty = TRUE), path)
  invisible(NULL)
}

# ---------------------------------------------------------------------------
# System prompt builder
# ---------------------------------------------------------------------------

#' Build the codeagent system prompt
#'
#' @param settings List. Output of [load_settings()].
#' @param cwd Character. Working directory.
#' @return Character(1). The full system prompt.
#' @keywords internal
.build_system_prompt <- function(settings, cwd = getwd()) {
  parts <- character(0)

  parts <- c(parts, paste0(
    "You are codeagent, an AI coding assistant for R.\n",
    "Working directory: ", cwd, "\n",
    "Date: ", format(Sys.Date()), "\n",
    "Model: ", settings$model
  ))

  # CLAUDE.md content
  if (!is.null(settings$claude_md) && nzchar(settings$claude_md)) {
    parts <- c(parts, paste0(
      "\n---\n",
      "## Project Instructions (CLAUDE.md)\n\n",
      settings$claude_md
    ))
  }

  # Skill list (progressive disclosure: names + descriptions only)
  skill_hint <- tryCatch(
    build_skill_hint(cwd = cwd, max_tokens = 1000L),
    error = function(e) NULL
  )
  if (!is.null(skill_hint) && nzchar(skill_hint)) {
    parts <- c(parts, paste0("\n---\n", skill_hint))
  }

  # Permission mode
  parts <- c(parts, paste0(
    "\n---\n",
    "Permission mode: ", settings$permission_mode, "\n",
    "Max turns: ", settings$max_turns
  ))

  paste(parts, collapse = "\n")
}

# ---------------------------------------------------------------------------
# System-reminder builder (dynamic, injected per-turn into user message)
# ---------------------------------------------------------------------------

#' Build a system-reminder block for dynamic per-turn context injection
#'
#' Mirrors Claude Code's `<system-reminder>` pattern: ephemeral context that
#' is appended to the user message rather than the system prompt, so it
#' doesn't break prompt caching.
#'
#' @param settings List. Output of [load_settings()].
#' @param iteration Integer. Current agent loop iteration.
#' @param cwd Character. Working directory.
#' @return Character(1). The reminder block, or `""` if nothing to inject.
#' @keywords internal
.build_system_reminder <- function(settings, iteration = 1L, cwd = getwd()) {
  lines <- character(0)

  # Current date/time (changes each turn, so must NOT be in system prompt)
  lines <- c(lines, sprintf("Current date/time: %s", format(Sys.time(), "%Y-%m-%d %H:%M %Z")))

  # Iteration count
  lines <- c(lines, sprintf("Agent loop iteration: %d", as.integer(iteration)))

  # Working directory (in case cwd changes)
  lines <- c(lines, sprintf("Working directory: %s", cwd))

  # Auto-memory recall (first iteration only; the model retains it thereafter).
  if (as.integer(iteration) <= 1L) {
    recall <- tryCatch(recall_memories(), error = function(e) "")
    if (nzchar(recall)) lines <- c(lines, "", recall)
  }

  if (length(lines) == 0L) return("")
  paste0("<system-reminder>\n", paste(lines, collapse = "\n"), "\n</system-reminder>")
}
