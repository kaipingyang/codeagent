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
  provider          = NULL,      # ellmer chat_* factory: "openai_compatible",
                                  # "anthropic", "ollama", "databricks", "deepseek",
                                  # "google_gemini", "groq", "openai", "github",
                                  # "vllm", "lmstudio", ...
                                  # NULL -> auto-detect from base_url
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
  rag                = FALSE,

  # R session environment context injection (gander-inspired).
  # When TRUE, the first system-reminder includes ls() + data.frame schemas
  # from .GlobalEnv so the agent knows what objects exist without a tool call.
  inject_r_env       = FALSE,

  # File-tool set: "core" (codeagent Read/Write/Edit/... on ANY path; default),
  # "btw" (btw hash-anchored/atomic tools, restricted to cwd), or "both" (the
  # LLM picks per task). See references/plan/14-tool-reuse-and-selection.md.
  file_tools         = "core",

  # Mid-loop compaction (Plan B): compact between tool rounds via on_tool_result.
  # midloop_compact = cheap budget-aware micro snip (ON by default, matches
  # Claude Code default-on compaction; only acts near the context limit).
  # midloop_full_compact = also run the full two-level LLM compact mid-loop when
  # a snip isn't enough (OFF by default -- it makes a blocking model call
  # mid-stream). See references/plan/13-mid-loop-compaction.md.
  midloop_compact      = TRUE,
  midloop_full_compact = FALSE,

  # Data exploration tool (ExploreData). TRUE = always register (default);
  # FALSE = opt-out (batch/non-interactive contexts).
  explore_data       = TRUE,

  # Shiny app: auto-restore the most recent session on startup (mirrors
  # `codeagent chat --continue`). TRUE = resume last conversation (default);
  # FALSE = open a fresh session each time.
  auto_continue      = TRUE
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
  if (nzchar(env_limit)) {
    settings$model_limit <- as.integer(env_limit)
  } else {
    # Resolve the context window dynamically from the model (Claude Code:
    # getContextWindowForModel) instead of the hard-coded 200K default.
    settings$model_limit <- .model_context_window(settings$model %||% "")
  }

  env_base_url <- Sys.getenv("CODEAGENT_BASE_URL", "")
  if (nzchar(env_base_url)) settings$base_url <- env_base_url

  # Small/fast model for compaction/classification (mirrors ANTHROPIC_SMALL_FAST_MODEL)
  env_small <- Sys.getenv("CODEAGENT_SMALL_FAST_MODEL", "")
  if (nzchar(env_small)) settings$small_fast_model <- env_small

  # Tier -> real-endpoint map (built from env vars, used by /model sonnet etc.)
  settings$tier_models <- .build_tier_models()

  # Derive PermissionRule list from permissions.allow / .deny / .ask
  settings$rules <- .permissions_to_rules(settings$permissions)

  # apiKeyHelper: run the declared command to obtain the API key when the
  # env var is not already set (mirrors Claude Code's apiKeyHelper behaviour).
  # The JSON field name is camelCase ("apiKeyHelper") matching Claude Code;
  # .CODEAGENT_DEFAULTS uses snake_case ("api_key_helper"). Accept both.
  # Fallback: if no helper is configured, try reading ~/.Renviron directly so
  # the REPL works under --vanilla without any explicit configuration.
  if (!nzchar(Sys.getenv("CODEAGENT_API_KEY", ""))) {
    helper_cmd <- settings$apiKeyHelper %||% settings$api_key_helper %||% NULL
    key <- NULL
    if (!is.null(helper_cmd) && nzchar(helper_cmd)) {
      # Run the user-configured helper command and use its stdout as the key.
      key <- tryCatch(
        trimws(system(helper_cmd, intern = TRUE, ignore.stderr = TRUE)),
        error = function(e) character(0))
    } else {
      # Built-in fallback: read CODEAGENT_API_KEY from ~/.Renviron directly.
      # --vanilla Rscript skips .Renviron; we read it ourselves so users only
      # need to set CODEAGENT_API_KEY in ~/.Renviron and nothing else.
      renviron <- path.expand("~/.Renviron")
      if (file.exists(renviron)) {
        lines <- tryCatch(readLines(renviron, warn = FALSE), error = function(e) character(0))
        rx <- grep("^CODEAGENT_API_KEY[[:space:]]*=", lines, value = TRUE)
        if (length(rx)) {
          parts <- strsplit(rx[[1L]], "=", fixed = TRUE)[[1L]]
          if (length(parts) >= 2L) {
            raw <- trimws(paste(parts[-1L], collapse = "="))
            key <- gsub('["\']', "", raw)
          }
        }
      }
    }
    if (length(key) && nzchar(key[[1L]]))
      Sys.setenv(CODEAGENT_API_KEY = key[[1L]])
  }

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
  # Check all conventional agent-instruction file names (Claude Code / btw /
  # Agents.md / llms.txt) so codeagent works regardless of which convention
  # the project uses. Mirrors side's context_files list.
  agent_filenames <- c("CLAUDE.md", "btw.md", "AGENTS.md", "llms.txt")
  walk <- character(0)
  path <- cwd
  for (i in seq_len(5L)) {
    for (fname in agent_filenames)
      walk <- c(walk, file.path(path, fname))
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
    cli::cli_abort("settings.json template not found in the codeagent package.")

  dest_dir <- if (identical(scope, "user")) {
    .get_codeagent_dir()
  } else {
    file.path(getwd(), ".codeagent")
  }
  dir.create(dest_dir, showWarnings = FALSE, recursive = TRUE)
  dest <- file.path(dest_dir, "settings.json")

  if (file.exists(dest))
    cli::cli_abort(c(
      "{.path {dest}} already exists.",
      "i" = "Edit it directly, or delete it first to regenerate from the template."
    ))

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
# Settings completeness check (called at REPL startup)
# ---------------------------------------------------------------------------

#' Check settings completeness and emit cli diagnostics
#'
#' Verifies that the critical settings (backend URL and API key) are present
#' after all sources have been merged and `apiKeyHelper` has been run.
#' Emits `cli_alert_warning` + actionable hints for each gap. Intended to run
#' once at `codeagent_console()` startup so users see the problem immediately
#' rather than getting an opaque HTTP 401 on their first message.
#'
#' @param settings List from [load_settings()].
#' @return Invisibly, a character vector of issue descriptions (empty = clean).
#' @keywords internal
.check_settings_completeness <- function(settings) {
  issues <- character(0)

  # 1. API key
  api_key <- Sys.getenv("CODEAGENT_API_KEY", "")
  if (!nzchar(api_key)) {
    issues <- c(issues, "api_key")
    cli::cli_alert_warning(
      "CODEAGENT_API_KEY is not set -- requests will fail with HTTP 401.")
    cli::cli_bullets(c(
      "i" = "Add to {.file ~/.Renviron}: {.code CODEAGENT_API_KEY=<token>}",
      "i" = paste0("Or set {.code apiKeyHelper} in ",
                   "{.file ~/.codeagent/settings.json} to a shell command that ",
                   "prints the key, e.g. {.code \"cat ~/.secret/api_key\"}")
    ))
  }

  # 2. Base URL (required for OpenAI-compatible gateways; not needed for Anthropic direct)
  base_url <- settings$base_url %||% Sys.getenv("CODEAGENT_BASE_URL", "")
  if (!nzchar(base_url) && !nzchar(Sys.getenv("ANTHROPIC_API_KEY", ""))) {
    issues <- c(issues, "base_url")
    cli::cli_alert_warning(
      "Neither CODEAGENT_BASE_URL nor ANTHROPIC_API_KEY is set.")
    cli::cli_bullets(c(
      "i" = paste0("For Databricks/OpenAI-compatible gateways, set ",
                   "{.code CODEAGENT_BASE_URL} in {.file ~/.Renviron} or ",
                   "the {.code env} block of {.file ~/.codeagent/settings.json}"),
      "i" = "For direct Anthropic API, set {.code ANTHROPIC_API_KEY}"
    ))
  }

  # 3. Model
  if (!nzchar(settings$model %||% "")) {
    issues <- c(issues, "model")
    cli::cli_alert_warning("No model is configured.")
    cli::cli_bullets(c(
      "i" = paste0("Set {.code CODEAGENT_MODEL} or add ",
                   "{.code \"model\": \"your-model\"} to settings.json")
    ))
  }

  if (length(issues)) cat("\n")
  invisible(issues)
}
