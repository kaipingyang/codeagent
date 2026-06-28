#' @title Permission System
#' @description Six-mode permission system mirroring Claude Code's permission model.
#' @name permissions
#' @keywords internal
#' @importFrom R6 R6Class
NULL

# ---------------------------------------------------------------------------
# Permission modes
# ---------------------------------------------------------------------------

#' Permission modes for codeagent
#'
#' A named list of the six permission modes, mirroring Claude Code's design.
#'
#' * `default`      -- Reads auto-allow; writes and shell execution require user confirmation.
#' * `plan`         -- Read-only mode; all non-read tools are rejected.
#' * `accept_edits` -- File edits auto-allow; Bash still requires confirmation.
#' * `bypass`       -- Almost all operations auto-approved.
#' * `dont_ask`     -- Operations that would ask are auto-rejected (CI/CD).
#' * `auto`         -- AI classifier (haiku model) decides automatically.
#'
#' @export
PermissionMode <- list(
  DEFAULT      = "default",
  PLAN         = "plan",
  ACCEPT_EDITS = "accept_edits",
  BYPASS       = "bypass",
  DONT_ASK     = "dont_ask",
  AUTO         = "auto"
)

# Tools that are always read-only (safe to auto-allow in all non-plan modes)
.READONLY_TOOLS <- c(
  "Read", "Glob", "Grep", "LS", "WebFetch", "WebSearch",
  "TaskGet", "TaskList", "NotebookRead"
)

# Tools auto-allowed in accept_edits mode
.EDIT_TOOLS <- c("Write", "Edit", "MultiEdit")

# ---------------------------------------------------------------------------
# Core permission check
# ---------------------------------------------------------------------------

#' Check whether a tool call is permitted
#'
#' Evaluates the permission decision for a single tool call, applying all
#' relevant rules in priority order.
#'
#' @param tool_name Character(1). Name of the tool (e.g. `"Bash"`, `"Write"`).
#' @param mode Character(1). One of the values in [PermissionMode].
#' @param rules List of [PermissionRule()] objects (highest priority first).
#' @param tool_input List or NULL. Tool arguments (used for Bash read-only detection).
#' @return Character(1): `"allow"`, `"deny"`, or `"ask"`.
#' @export
check_permission <- function(tool_name, mode = "default",
                              rules = list(), tool_input = NULL) {
  is_readonly <- tool_name %in% .READONLY_TOOLS

  # 1. Plan mode: block all non-read operations immediately
  if (identical(mode, "plan") && !is_readonly) return("deny")

  # 2. User-defined rules (evaluated in order, first match wins)
  for (rule in rules) {
    if (.rule_matches(rule, tool_name)) return(rule$behavior)
  }

  # 3. accept_edits: file edit tools auto-allowed
  if (identical(mode, "accept_edits") && tool_name %in% .EDIT_TOOLS)
    return("allow")

  # 4. bypass: everything allowed (killswitch can override externally)
  if (identical(mode, "bypass")) return("allow")

  # 5. dont_ask: read-only tools still pass; "ask" decisions become "deny" (CI/CD)
  if (identical(mode, "dont_ask")) {
    if (is_readonly) return("allow")
    return("deny")
  }

  # 6. auto: AI classifier via haiku model
  if (identical(mode, "auto")) return(.auto_classify_tool(tool_name, tool_input))

  # 7. default: read-only tools auto-allow, rest ask
  if (is_readonly) return("allow")

  # Bash read-only optimisation: ls, cat, grep etc. auto-allow in default mode
  if (identical(tool_name, "Bash") && !is.null(tool_input)) {
    cmd <- tool_input[["command"]] %||% ""
    if (.is_bash_readonly(cmd)) return("allow")
  }

  "ask"
}

# ---------------------------------------------------------------------------
# Rule matching
# ---------------------------------------------------------------------------

.rule_matches <- function(rule, tool_name) {
  pattern <- rule$tool_name %||% "*"
  if (identical(pattern, "*")) return(TRUE)
  # Support simple wildcards: "npm test:*"
  if (grepl("*", pattern, fixed = TRUE)) {
    regex <- paste0("^", gsub("*", ".*", pattern, fixed = TRUE), "$")
    return(grepl(regex, tool_name))
  }
  identical(pattern, tool_name)
}

# ---------------------------------------------------------------------------
# Bash read-only detection
# ---------------------------------------------------------------------------

.BASH_READONLY_PATTERNS <- c(
  "^ls\\b", "^cat\\b", "^echo\\b", "^grep\\b", "^find\\b",
  "^head\\b", "^tail\\b", "^wc\\b", "^pwd$", "^which\\b",
  "^type\\b", "^env\\b", "^printenv\\b", "^uname\\b",
  "^date\\b", "^whoami$", "^id$", "^df\\b", "^du\\b",
  "^ps\\b", "^top\\b", "^htop\\b", "^man\\b",
  "^rg\\b", "^git log\\b", "^git diff\\b", "^git status\\b",
  "^git show\\b", "^git branch\\b"
)

# Pre-compiled combined regex for O(1) readonly detection instead of O(n) per-pattern grepl
.BASH_READONLY_REGEX <- paste(.BASH_READONLY_PATTERNS, collapse = "|")

.is_bash_readonly <- function(command) {
  grepl(.BASH_READONLY_REGEX, trimws(command), perl = TRUE)
}

# ---------------------------------------------------------------------------
# Auto classifier (haiku model)
# ---------------------------------------------------------------------------

.auto_classify_tool <- function(tool_name, tool_input = NULL) {
  # Safe tools that never need classification
  if (tool_name %in% .READONLY_TOOLS) return("allow")

  # Use haiku to classify
  result <- tryCatch({
    classifier <- ellmer::chat_anthropic(
      model = .HAIKU_MODEL,
      system_prompt = paste0(
        "You are a security classifier. Answer only 'allow' or 'deny'.\n",
        "Determine if the following tool call is safe to execute automatically."
      )
    )
    input_str <- if (!is.null(tool_input))
      jsonlite::toJSON(tool_input, auto_unbox = TRUE) else "{}"
    response  <- classifier$chat(
      paste0("Tool: ", tool_name, "\nInput: ", input_str)
    )
    trimws(tolower(response))
  }, error = function(e) "ask")

  if (result %in% c("allow", "deny")) result else "ask"
}

# ---------------------------------------------------------------------------
# Denial tracker
# ---------------------------------------------------------------------------

#' Track permission denials and emit warnings at thresholds
#'
#' Mirrors Claude Code's `denialTracking.ts` behaviour:
#' * 3 consecutive denials -> warning to reconsider permission mode
#' * 20 total denials     -> warning to review permission configuration
#'
#' @export
DenialTracker <- R6::R6Class(
  "DenialTracker",
  private = list(consecutive = 0L, total = 0L),
  public  = list(
    #' @description Record a denial event.
    record_denial = function() {
      private$consecutive <- private$consecutive + 1L
      private$total       <- private$total + 1L
      if (private$consecutive >= .DENIAL_WARN_CONSECUTIVE)
        warning("[codeagent] ", .DENIAL_WARN_CONSECUTIVE,
                " consecutive denials \u2014 consider switching permission mode.",
                call. = FALSE)
      if (private$total >= .DENIAL_WARN_TOTAL)
        warning("[codeagent] ", .DENIAL_WARN_TOTAL,
                " total denials \u2014 review your permission configuration.",
                call. = FALSE)
    },
    #' @description Record a successful tool execution (resets consecutive count).
    record_success = function() {
      private$consecutive <- 0L
    },
    #' @description Return current counts.
    counts = function() {
      list(consecutive = private$consecutive, total = private$total)
    }
  )
)
