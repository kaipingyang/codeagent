#' @title Dynamic context-window resolution
#' @description Resolves a model's context window and the auto-compaction
#'   threshold dynamically, instead of hard-coding 200K. Mirrors Claude Code:
#'   `src/utils/context.ts` (`getContextWindowForModel`,
#'   `getEffectiveContextWindowSize`) and `src/services/compact/autoCompact.ts`
#'   (`getAutoCompactThreshold`).
#'
#'   Resolution order for the raw window (highest priority first):
#'   1. `CODEAGENT_MAX_CONTEXT_TOKENS` env override (= CLAUDE_CODE_MAX_CONTEXT_TOKENS)
#'   2. `[1m]` suffix in the model name -> 1,000,000 (= has1mContext)
#'   3. Known-model capability table / provider-reported value (>= 100K trusted)
#'   4. `.MODEL_CONTEXT_WINDOW_DEFAULT` (200K)
#' @name context_window
#' @keywords internal
NULL

# Known context windows (max INPUT tokens), matched by substring, longest key
# wins. Mirrors getModelCapability.max_input_tokens (modelCapabilities.ts:75) --
# Claude Code likewise maintains a table plus provider detection.
.MODEL_CONTEXT_WINDOW_TABLE <- c(
  "claude-3-5-haiku"  = 200000L,
  "claude-3-5-sonnet" = 200000L,
  "claude-3-7-sonnet" = 200000L,
  "claude-haiku-4"    = 200000L,
  "claude-sonnet-4"   = 200000L,
  "claude-opus-4"     = 200000L,
  "claude"            = 200000L,
  "gpt-4.1"           = 1000000L,
  "gpt-4o"            = 128000L,
  "gpt-4-turbo"       = 128000L,
  "gpt-5"             = 400000L,
  "gpt-4"             = 128000L,
  "gpt41"             = 1000000L,
  "o1"                = 200000L,
  "o3"                = 200000L,
  "o4"                = 200000L,
  "gemini-1.5-pro"    = 2000000L,
  "gemini-1.5-flash"  = 1000000L,
  "gemini-2"          = 1000000L,
  "gemini"            = 1000000L,
  "deepseek-r1"       = 131072L,
  "deepseek-v3"       = 131072L,
  "deepseek"          = 131072L,
  "llama-3"           = 128000L,
  "qwen"              = 131072L,
  "mistral"           = 128000L
)

# Max OUTPUT tokens by model (used to size the reserve). Mirrors Claude Code
# getMaxOutputTokensForModel (claude.ts). Substring match, longest key wins.
.MODEL_MAX_OUTPUT_TABLE <- c(
  "claude-3-5-haiku"  = 8192L,
  "claude-3-5-sonnet" = 8192L,
  "claude-3-7-sonnet" = 65536L,
  "claude-sonnet-4"   = 65536L,
  "claude-opus-4"     = 32000L,
  "claude-haiku-4"    = 32000L,
  "claude"            = 8192L,
  "o1"                = 100000L,
  "o3"                = 100000L,
  "gpt-5"             = 128000L,
  "gpt"               = 16384L,
  "gemini"            = 8192L,
  "deepseek"          = 8192L
)

# Substring lookup with longest-key-wins. Returns NA_integer_ when no match.
.table_lookup_prefix <- function(model, table) {
  if (is.null(model) || !is.character(model) || !nzchar(model)) return(NA_integer_)
  m    <- tolower(model)
  keys <- names(table)
  hit  <- keys[vapply(keys, function(k) grepl(k, m, fixed = TRUE), logical(1))]
  if (length(hit) == 0L) return(NA_integer_)
  key <- hit[which.max(nchar(hit))]
  as.integer(table[[key]])
}

# Try to read the context window the provider itself reports (e.g. OpenRouter
# `context_length`, Ollama model info). ellmer does not expose a stable API for
# this yet, so this is a best-effort hook that returns NA when unavailable.
.provider_reported_window <- function(chat) {
  if (is.null(chat)) return(NA_integer_)
  tryCatch({
    md <- if ("get_model_info" %in% names(chat)) chat$get_model_info() else NULL
    v  <- md$context_length %||% md$context_window %||% md$max_input_tokens %||% NA
    if (is.numeric(v) && length(v) == 1L && !is.na(v) && v > 0) as.integer(v) else NA_integer_
  }, error = function(e) NA_integer_)
}

# = getModelCapability.max_input_tokens (modelCapabilities.ts:75): provider
# value if exposed, else the built-in table.
.model_capability_tokens <- function(model, chat = NULL) {
  pv <- .provider_reported_window(chat)
  if (!is.na(pv)) return(pv)
  .table_lookup_prefix(model, .MODEL_CONTEXT_WINDOW_TABLE)
}

# = getMaxOutputTokensForModel (claude.ts): reserve for the model's output.
.max_output_tokens_for_model <- function(model) {
  v <- .table_lookup_prefix(model, .MODEL_MAX_OUTPUT_TABLE)
  if (is.na(v)) .MAX_OUTPUT_TOKENS_FOR_SUMMARY else v
}

#' Resolve a model's raw context window (= getContextWindowForModel, context.ts:51)
#' @param model Character. Model id/name.
#' @param chat An `ellmer::Chat` or NULL (used to read provider-reported window).
#' @return Integer token count.
#' @keywords internal
.model_context_window <- function(model, chat = NULL) {
  # 1. Env override (= CLAUDE_CODE_MAX_CONTEXT_TOKENS)
  env <- Sys.getenv("CODEAGENT_MAX_CONTEXT_TOKENS", "")
  if (nzchar(env)) {
    v <- suppressWarnings(as.integer(env))
    if (!is.na(v) && v > 0L) return(v)
  }
  # 2. [1m] suffix (= has1mContext, context.ts:35)
  if (!is.null(model) && grepl("\\[1m\\]", model, ignore.case = TRUE)) return(1000000L)
  # 3. Capability (provider value or table); only trust >= 100K (= CC guard)
  cap <- .model_capability_tokens(model, chat)
  if (!is.na(cap) && cap >= 100000L) return(cap)
  # 4. Default
  .MODEL_CONTEXT_WINDOW_DEFAULT
}

#' Effective window after reserving output tokens (= getEffectiveContextWindowSize)
#' @inheritParams .model_context_window
#' @return Integer token count (window minus output reserve).
#' @keywords internal
.effective_context_window <- function(model, chat = NULL) {
  reserve <- min(.max_output_tokens_for_model(model), .MAX_OUTPUT_TOKENS_FOR_SUMMARY)
  cw      <- .model_context_window(model, chat)
  acw     <- Sys.getenv("CODEAGENT_AUTO_COMPACT_WINDOW", "")   # = CLAUDE_CODE_AUTO_COMPACT_WINDOW
  if (nzchar(acw)) {
    v <- suppressWarnings(as.integer(acw))
    if (!is.na(v) && v > 0L) cw <- min(cw, v)
  }
  cw - reserve
}

#' Auto-compaction threshold (= getAutoCompactThreshold, autoCompact.ts:72)
#' @inheritParams .model_context_window
#' @return Integer token count at/above which auto-compaction should trigger.
#' @keywords internal
.auto_compact_threshold <- function(model, chat = NULL) {
  .effective_context_window(model, chat) - .AUTOCOMPACT_BUFFER_TOKENS
}

# Auto-compaction on unless explicitly disabled (= CLAUDE_CODE_DISABLE_COMPACT).
auto_compact_enabled <- function() {
  Sys.getenv("CODEAGENT_DISABLE_COMPACT", "") == ""
}

#' Context-budget warning state (= calculateTokenWarningState, autoCompact.ts)
#'
#' Computes how much context is left and which thresholds have been crossed,
#' for the "X% context left" indicator in the REPL banner and Shiny status bar.
#'
#' @param token_usage Integer. Current token usage (see [token_count_with_estimation]).
#' @param model Character. Model id/name.
#' @param chat An `ellmer::Chat` or NULL.
#' @return A list: `percent_left`, `above_warning`, `above_error`,
#'   `above_compact`, `at_blocking`.
#' @keywords internal
calculate_token_warning_state <- function(token_usage, model, chat = NULL) {
  token_usage <- as.numeric(token_usage %||% 0)
  eff         <- .effective_context_window(model, chat)
  enabled     <- auto_compact_enabled()
  threshold   <- if (enabled) .auto_compact_threshold(model, chat) else eff
  list(
    percent_left  = max(0L, as.integer(round((threshold - token_usage) / threshold * 100))),
    above_warning = token_usage >= threshold - .WARNING_THRESHOLD_BUFFER,
    above_error   = token_usage >= threshold - .ERROR_THRESHOLD_BUFFER,
    above_compact = enabled && token_usage >= .auto_compact_threshold(model, chat),
    at_blocking   = token_usage >= eff - .MANUAL_COMPACT_BUFFER
  )
}
