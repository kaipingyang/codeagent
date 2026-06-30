#' @title Settings System
#' @description Configuration loading for codeagent.
#'   Priority (highest to lowest): environment variables >
#'   `~/.codeagent/settings.json` > `.codeagent/settings.json` > CLAUDE.md.
#'
#'   The `env` block in settings.json is applied via `Sys.setenv()` before the
#'   environment-variable layer is read, so it works even under `Rscript
#'   --vanilla` (which skips `.Renviron`). This mirrors Claude Code's behaviour.
#' @name settings
#' @keywords internal
NULL

# ---------------------------------------------------------------------------
# Defaults  (mirrors Claude Code settings.json top-level keys)
# ---------------------------------------------------------------------------

.CODEAGENT_DEFAULTS <- list(
  # Core model / backend
  model             = "claude-sonnet-4-6",
  base_url          = NULL,      # non-NULL -> OpenAI-compatible endpoint
  api_key_env       = NULL,      # env var name for the API key (auto-detect)
  small_fast_model  = NULL,      # set by CODEAGENT_SMALL_FAST_MODEL; NULL -> .HAIKU_MODEL
  tier_models       = list(),    # named list: sonnet/opus/haiku -> real endpoint
  fallback_model    = NULL,      # character vector, not merged across files

  # Context / turns
  max_turns         = 100L,
  model_limit       = 200000L,
  max_output_tokens = 8192L,

  # Behaviour flags (Claude Code schema)
  thinking               = FALSE,
  stream                 = TRUE,
  effort_level           = NULL,    # "low"|"medium"|"high"|"xhigh"
  include_coauthored_by  = TRUE,    # includeCoAuthoredBy
  auto_compact_enabled   = TRUE,    # autoCompactEnabled
  cleanup_period_days    = 30L,     # cleanupPeriodDays

  # UI / presentation (stored, not yet all wired)
  theme         = "default",
  output_style  = NULL,   # outputStyle (placeholder)
  status_line   = NULL,   # statusLine  (placeholder)

  # Permissions (parallel Claude Code structure)
  permission_mode     = "default",
  permissions         = list(allow = list(), deny = list(),
                              ask = list(), additionalDirectories = list(),
                              defaultMode = "default"),
  rules               = list(),   # PermissionRule objects derived from permissions

  # MCP
  enable_all_project_mcp_servers = FALSE,
  enabled_mcp_json_servers       = character(0),
  disabled_mcp_json_servers      = character(0),

  # Misc (placeholder / stored)
  hooks              = list(),
  api_key_helper     = NULL,   # apiKeyHelper (placeholder)
  env                = list(), # env block (applied; stored for reference)

  # Bash sandbox (best-effort env scrub + network deny; see sandbox.R)
  sandbox            = list(enabled = FALSE, allow_network = TRUE),

  # Codebase RAG retrieval (opt-in; indexing is costly). See rag.R.
  rag                = FALSE
)

# ---------------------------------------------------------------------------
# Main entry point
# ---------------------------------------------------------------------------

#' Load codeagent settings
#'
#' Merges configuration from all sources in priority order and applies the
#' `env` block from settings.json so that environment variables are available
#' even when running under `Rscript --vanilla`.
#'
#' @param cwd Character. Working directory (used to locate `.codeagent/settings.json`
#'   and `CLAUDE.md`). Defaults to `getwd()`.
#' @return A named list of settings.
#' @export
load_settings <- function(cwd = getwd()) {
  settings <- .CODEAGENT_DEFAULTS

  # Layer 3 & 2: JSON files (user then project; project wins)
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

  # Apply env block BEFORE reading env-var layer.  Claude Code does the same:
  # the env block is injected into the session so downstream Sys.getenv() calls
  # see the overrides regardless of how the process was launched.
  if (is.list(settings$env) && length(settings$env) > 0L) {
    tryCatch(
      do.call(Sys.setenv, lapply(settings$env, as.character)),
      error = function(e)
        warning("Could not apply settings.json env block: ", conditionMessage(e),
                call. = FALSE)
    )
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

  # Small/fast model for compaction/classification (mirrors ANTHROPIC_SMALL_FAST_MODEL)
  env_small <- Sys.getenv("CODEAGENT_SMALL_FAST_MODEL", "")
  if (nzchar(env_small)) settings$small_fast_model <- env_small

  # Tier -> real-endpoint map (built from env vars, used by /model sonnet etc.)
  settings$tier_models <- .build_tier_models()

  # Derive PermissionRule list from permissions.allow / .deny / .ask
  settings$rules <- .permissions_to_rules(settings$permissions)

  # CLAUDE.md (loaded as context, not merged as settings)
  settings$claude_md <- .load_claude_md(cwd)

  settings
}

# ---------------------------------------------------------------------------
# Tier model map
# ---------------------------------------------------------------------------

# Build named list of tier -> real endpoint from env vars.
# Mirrors: ANTHROPIC_DEFAULT_SONNET_MODEL / ANTHROPIC_DEFAULT_OPUS_MODEL /
#          ANTHROPIC_SMALL_FAST_MODEL  in Claude Code's ~/.claude/settings.json
.build_tier_models <- function() {
  tiers <- list()
  sonnet <- Sys.getenv("CODEAGENT_DEFAULT_SONNET_MODEL", "")
  opus   <- Sys.getenv("CODEAGENT_DEFAULT_OPUS_MODEL",   "")
  haiku  <- Sys.getenv("CODEAGENT_SMALL_FAST_MODEL",     "")
  if (nzchar(sonnet)) tiers[["sonnet"]] <- sonnet
  if (nzchar(opus))   tiers[["opus"]]   <- opus
  if (nzchar(haiku))  tiers[["haiku"]]  <- haiku
  tiers
}

# ---------------------------------------------------------------------------
# permissions.{allow,deny,ask} -> PermissionRule list
# ---------------------------------------------------------------------------

# Parse a Claude Code-style pattern string like "Bash(npm run test *)" into
# (tool_name, rule_content).  No parentheses -> tool_name only.
.parse_permission_pattern <- function(pattern) {
  pattern <- trimws(pattern %||% "")
  if (!nzchar(pattern)) return(NULL)
  m <- regexec("^([A-Za-z_][A-Za-z0-9_]*)\\((.*)\\)$", pattern)
  caps <- regmatches(pattern, m)[[1L]]
  if (length(caps) == 3L) {
    list(tool_name = caps[[2L]], rule_content = caps[[3L]])
  } else {
    list(tool_name = pattern, rule_content = NULL)
  }
}

# Convert settings$permissions lists into PermissionRule objects.
# jsonlite simplifyVector=TRUE: non-empty array -> character vector,
# empty array -> list() of length 0.  Handle both shapes.
.permissions_to_rules <- function(perms) {
  if (!is.list(perms)) return(list())
  rules <- list()
  for (behavior in c("allow", "deny", "ask")) {
    patterns <- perms[[behavior]]
    if (!length(patterns)) next
    if (is.character(patterns)) patterns <- as.list(patterns)
    for (p in patterns) {
      parsed <- tryCatch(.parse_permission_pattern(p), error = function(e) NULL)
      if (is.null(parsed)) next
      rule <- tryCatch(
        PermissionRule(parsed$tool_name, behavior = behavior,
                       source = "settings", rule_content = parsed$rule_content),
        error = function(e) NULL
      )
      if (!is.null(rule)) rules <- c(rules, list(rule))
    }
  }
  rules
}

# ---------------------------------------------------------------------------
# CLAUDE.md loading
# ---------------------------------------------------------------------------

#' Load and merge CLAUDE.md from all levels
#'
#' Mirrors Claude Code's multi-level memory: collect CLAUDE.md from the user
#' home (`~/.claude/CLAUDE.md`, `~/.codeagent/CLAUDE.md`) plus every level from
#' the working directory up to the filesystem root (max 5 hops), then merge them
#' in priority order (user first, then outer-to-inner project dirs) with section
#' headers showing each source.  More-specific (deeper) files appear later so
#' they visually override.  Duplicate paths are de-duplicated.
#'
#' @param cwd Character. Starting directory.
#' @return Character(1) with merged contents, or NULL if none found.
#' @keywords internal
.load_claude_md <- function(cwd) {
  candidates <- character(0)

  # User-level memory (lowest priority; appears first)
  home <- path.expand("~")
  candidates <- c(candidates,
                  file.path(home, ".claude",    "CLAUDE.md"),
                  file.path(home, ".codeagent", "CLAUDE.md"))

  # Project-level: walk up from cwd to root, collect deepest-last so that
  # more-specific dirs override.  Build outer->inner by reversing the walk.
  walk <- character(0)
  path <- cwd
  for (i in seq_len(5L)) {
    walk <- c(walk, file.path(path, "CLAUDE.md"))
    parent <- dirname(path)
    if (parent == path) break
    path <- parent
  }
  candidates <- c(candidates, rev(walk))   # outermost first, cwd last

  # Read existing, de-duplicated by normalized path, preserving order.
  seen  <- character(0)
  parts <- character(0)
  for (cand in candidates) {
    if (!file.exists(cand)) next
    norm <- tryCatch(normalizePath(cand, mustWork = FALSE), error = function(e) cand)
    if (norm %in% seen) next
    seen <- c(seen, norm)
    lines <- tryCatch(readLines(cand, warn = FALSE), error = function(e) NULL)
    if (is.null(lines) || !length(lines)) next
    body <- paste(lines, collapse = "\n")
    if (!nzchar(trimws(body))) next
    parts <- c(parts, sprintf("<!-- source: %s -->\n%s", norm, body))
  }

  if (!length(parts)) return(NULL)
  paste(parts, collapse = "\n\n")
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

#' Create a codeagent settings.json file
#'
#' Copies the package template to `~/.codeagent/settings.json` (user scope)
#' or `.codeagent/settings.json` (project scope).  The template uses placeholder
#' values -- edit it to add real endpoint names and tier mappings.  Store your
#' API key in `.Renviron` as `CODEAGENT_API_KEY`, never in settings.json.
#'
#' @param scope Character. `"user"` (default) writes to `~/.codeagent/`;
#'   `"project"` writes to `.codeagent/` in the current directory.
#' @param open Logical. Open the file after creation when running in RStudio/
#'   Positron (requires rstudioapi).
#' @return Invisible character. Path to created file.
#' @export
use_codeagent_settings <- function(scope = c("user", "project"),
                                   open  = interactive()) {
  scope <- match.arg(scope)
  template <- system.file("templates", "settings.json", package = "codeagent")
  if (!nzchar(template) || !file.exists(template))
    stop("settings.json template not found in codeagent package.", call. = FALSE)

  dest_dir <- if (identical(scope, "user")) {
    .get_codeagent_dir()
  } else {
    file.path(getwd(), ".codeagent")
  }
  dir.create(dest_dir, showWarnings = FALSE, recursive = TRUE)
  dest <- file.path(dest_dir, "settings.json")

  if (file.exists(dest))
    stop("'", dest, "' already exists.  Edit it directly or delete it first.",
         call. = FALSE)

  file.copy(template, dest)
  message("Created: ", dest)
  message("Next steps:")
  message("  1. Edit '", dest, "' -- replace placeholder endpoint names with real ones.")
  message("  2. Add CODEAGENT_API_KEY=<your-token> to your ~/.Renviron (never in settings.json).")
  message("  3. Restart R so the env block takes effect, then run: codeagent info")

  if (open && requireNamespace("rstudioapi", quietly = TRUE) &&
      rstudioapi::hasFun("navigateToFile"))
    rstudioapi::navigateToFile(dest)

  invisible(dest)
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
