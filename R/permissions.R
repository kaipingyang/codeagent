#' @title Permission System
#' @description Seven-mode permission system mirroring Claude Code's permission model.
#' @name permissions
#' @keywords internal
#' @importFrom R6 R6Class
NULL

# ---------------------------------------------------------------------------
# Permission modes
# ---------------------------------------------------------------------------

#' Permission modes for codeagent
#'
#' A named list of the seven permission modes, mirroring Claude Code's design.
#'
#' * `default`      -- Reads auto-allow; writes and shell execution require user confirmation.
#' * `plan`         -- Read-only mode; all non-read tools are rejected.
#' * `accept_edits` -- File edits auto-allow; Bash still requires confirmation.
#' * `bypass`       -- Almost all operations auto-approved.
#' * `dont_ask`     -- Operations that would ask are auto-rejected (CI/CD).
#' * `auto`         -- AI classifier (haiku model) decides automatically.
#' * `bubble`       -- Sub-agent mode: permission decisions bubble up to the
#'                     parent agent rather than being resolved locally.
#'
#' @export
PermissionMode <- list(
  DEFAULT      = "default",
  PLAN         = "plan",
  ACCEPT_EDITS = "accept_edits",
  BYPASS       = "bypass",
  DONT_ASK     = "dont_ask",
  AUTO         = "auto",
  BUBBLE       = "bubble"
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
    if (.rule_matches(rule, tool_name, tool_input)) return(rule$behavior)
  }

  # 3. accept_edits: file edit tools auto-allowed
  if (identical(mode, "accept_edits") && tool_name %in% .EDIT_TOOLS)
    return("allow")

  # 4. bypass: everything allowed
  if (identical(mode, "bypass")) return("allow")

  # 5. bubble: sub-agent mode -- permission bubbles up to parent; return "ask"
  #    so the parent agent's ask_fn handles it (not auto-denied like dont_ask)
  if (identical(mode, "bubble")) return("ask")

  # 6. dont_ask: read-only tools still pass; "ask" decisions become "deny" (CI/CD)
  if (identical(mode, "dont_ask")) {
    if (is_readonly) return("allow")
    return("deny")
  }

  # 7. auto: AI classifier via haiku model
  if (identical(mode, "auto")) return(.auto_classify_tool(tool_name, tool_input))

  # 8. default: read-only tools auto-allow, rest ask
  if (is_readonly) return("allow")

  # Bash read-only optimisation: ls, cat, grep etc. auto-allow in default mode
  if (identical(tool_name, "Bash") && !is.null(tool_input)) {
    cmd <- tool_input[["command"]] %||% ""
    if (.is_bash_readonly(cmd)) return("allow")
  }

  "ask"
}

# ---------------------------------------------------------------------------
# Rule matching (fine-grained, mirrors Claude Code "Bash(cmd *)" syntax)
# ---------------------------------------------------------------------------

# Glob-style match: "*" anywhere in pattern -> wildcard. Case-sensitive.
.glob_match <- function(pattern, text) {
  if (!nzchar(pattern %||% "")) return(TRUE)
  if (!grepl("*", pattern, fixed = TRUE)) return(identical(pattern, text))
  regex <- paste0("^", gsub("*", ".*", pattern, fixed = TRUE), "$")
  grepl(regex, text, perl = TRUE)
}

# Map tool name -> the key inside tool_input that represents the "target"
# (the thing the permission rule's content is matched against).
.rule_target_arg <- function(tool_name, tool_input) {
  if (is.null(tool_input)) return(NULL)
  key <- switch(tool_name,
    Bash      = "command",
    Read      = "file_path",
    Write     = "file_path",
    Edit      = "file_path",
    MultiEdit = "file_path",
    Glob      = "pattern",
    Grep      = "pattern",
    NULL
  )
  if (is.null(key)) return(NULL)
  val <- tool_input[[key]]
  if (is.character(val) && length(val) == 1L) val else NULL
}

# Check if a PermissionRule matches a given tool call.
# Step 1: tool_name must match (wildcard OK).
# Step 2: if rule has rule_content, match it against the relevant tool arg.
.rule_matches <- function(rule, tool_name, tool_input = NULL) {
  # Step 1: tool name
  name_pattern <- rule$tool_name %||% "*"
  if (!.glob_match(name_pattern, tool_name)) return(FALSE)

  # Step 2: rule_content (fine-grained, e.g. "npm run test *" for Bash)
  rc <- rule$rule_content
  if (is.null(rc) || !nzchar(rc)) return(TRUE)   # tool-level rule: name match is enough

  arg <- .rule_target_arg(tool_name, tool_input)
  if (is.null(arg)) return(FALSE)                  # content rule but no target arg -> no match
  .glob_match(rc, arg)
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

# ---------------------------------------------------------------------------
# Permission rule parsing from settings.json declarations
# (moved from settings.R -- belongs with the permission system)
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
