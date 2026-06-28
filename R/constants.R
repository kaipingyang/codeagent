#' @title Package-wide Constants
#' @description Central registry for all magic numbers and hardcoded strings
#'   used across codeagent subsystems. Editing values here propagates to every
#'   subsystem automatically.
#' @name constants
#' @keywords internal
NULL

# ---------------------------------------------------------------------------
# Model names
# ---------------------------------------------------------------------------

# Haiku model used for compaction, auto-classification, and sub-tasks
.HAIKU_MODEL <- "claude-haiku-4-5-20251001"

# Compact model for OpenAI-compatible (Databricks) endpoints
# Used by .make_compact_chat() when CODEAGENT_BASE_URL is set.
.HAIKU_MODEL_OPENAI_COMPAT <- "databricks-claude-haiku-4-5"

# ---------------------------------------------------------------------------
# Compaction thresholds
# ---------------------------------------------------------------------------

# How many tokens below the model limit to trigger compaction.
# For a 200K model: 200K - 33K = 167K trigger point.
.COMPACT_TRIGGER_MARGIN <- 33000L

# L1 (snip) triggers at the base threshold (0 additional margin)
.COMPACT_L1_MARGIN <- 0L

# L2 (session memory) triggers 15K above the base threshold
.COMPACT_L2_MARGIN <- 15000L

# L3 (full compact) triggers 30K above the base threshold
.COMPACT_L3_MARGIN <- 30000L

# L2: minimum tokens to retain in the summary
.COMPACT_L2_MIN_TOKENS <- 10000L

# L2: maximum tokens for the summary section
.COMPACT_L2_MAX_TOKENS <- 40000L

# L3: circuit breaker — silence after this many consecutive failures
.COMPACT_CIRCUIT_BREAKER_LIMIT <- 3L

# L3: maximum chars fed to the full-compact haiku agent
.COMPACT_FULL_TRUNCATE_CHARS <- 400000L

# ---------------------------------------------------------------------------
# Budget tracking
# ---------------------------------------------------------------------------

# Stop the agent loop when token usage reaches this fraction of the limit
.BUDGET_STOP_RATIO <- 0.9

# Minimum per-turn token growth; below this is considered "no progress"
.BUDGET_MIN_GROWTH <- 500L

# Stop after this many consecutive low-growth turns
.BUDGET_MAX_STALL_TURNS <- 3L

# Minimum iterations before budget stopping is considered
.BUDGET_MIN_ITERATIONS <- 3L

# ---------------------------------------------------------------------------
# Permission / denial tracking
# ---------------------------------------------------------------------------

# Emit a warning after this many consecutive denials
.DENIAL_WARN_CONSECUTIVE <- 3L

# Emit a warning after this many total denials
.DENIAL_WARN_TOTAL <- 20L

# ---------------------------------------------------------------------------
# Bash tool
# ---------------------------------------------------------------------------

# Default timeout (seconds) for bash_tool system2() calls
.BASH_TIMEOUT_DEFAULT <- 30L
