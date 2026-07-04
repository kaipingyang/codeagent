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

# L2: minimum tokens to retain in the summary
.COMPACT_L2_MIN_TOKENS <- 10000L

# L2: maximum tokens for the summary section
.COMPACT_L2_MAX_TOKENS <- 40000L

# L3: circuit breaker -- silence after this many consecutive failures
.COMPACT_CIRCUIT_BREAKER_LIMIT <- 3L

# L3: maximum chars fed to the full-compact haiku agent
.COMPACT_FULL_TRUNCATE_CHARS <- 400000L

# ---------------------------------------------------------------------------
# Claude Code-aligned context/compaction constants
# (src/services/compact/autoCompact.ts + src/utils/context.ts)
# ---------------------------------------------------------------------------

# Default context window when a model is unknown (context.ts:9
# MODEL_CONTEXT_WINDOW_DEFAULT).
.MODEL_CONTEXT_WINDOW_DEFAULT <- 200000L

# Output tokens reserved for the summary response (autoCompact.ts
# MAX_OUTPUT_TOKENS_FOR_SUMMARY).
.MAX_OUTPUT_TOKENS_FOR_SUMMARY <- 20000L

# Extra buffer below the effective window that triggers auto-compaction
# (autoCompact.ts:62 AUTOCOMPACT_BUFFER_TOKENS). 20000 + 13000 == 33000, i.e.
# the historical .COMPACT_TRIGGER_MARGIN for a 200K model.
.AUTOCOMPACT_BUFFER_TOKENS <- 13000L

# Warning / error / manual-compact buffers for the %-left indicator
# (autoCompact.ts WARNING/ERROR/MANUAL_COMPACT_BUFFER_TOKENS).
.WARNING_THRESHOLD_BUFFER <- 20000L
.ERROR_THRESHOLD_BUFFER   <- 20000L
.MANUAL_COMPACT_BUFFER    <- 3000L

# Circuit breaker: stop auto-compacting after this many consecutive failures
# (autoCompact.ts MAX_CONSECUTIVE_AUTOCOMPACT_FAILURES). Mirrors the existing
# .COMPACT_CIRCUIT_BREAKER_LIMIT.
.MAX_CONSECUTIVE_COMPACT_FAILS <- 3L

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
