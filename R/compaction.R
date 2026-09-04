#' @title Context Compaction System
#' @description Four-level context compaction mirroring Claude Code's design.
#'
#'   * L1 MicroCompact/Snip: replace old tool results with a placeholder
#'   * L2 Session Memory: incremental summary (10K-40K tokens retained)
#'   * L3 Full Compaction: fork agent generates a 9-section structured summary
#'   * L4 PTL Fallback: drop oldest turns on 413/prompt_too_long errors
#'
#'   Trigger threshold: `model_limit - 20000 - 13000` tokens (e.g. 167K for 200K model).
#'   Circuit breaker: 3 consecutive failures silence further compaction attempts.
#' @name compaction
#' @keywords internal
NULL

# ---------------------------------------------------------------------------
# Compact chat factory (uses OpenAI-compatible if CODEAGENT_BASE_URL is set)
# ---------------------------------------------------------------------------

# Creates a lightweight chat for compaction tasks.
# Falls back to chat_anthropic when no OpenAI endpoint is configured.
# The model arg should already be the real endpoint name (resolved by the
# caller from settings$small_fast_model or .HAIKU_MODEL). We no longer swap
# .HAIKU_MODEL -> .HAIKU_MODEL_OPENAI_COMPAT here; callers set the model.
.make_compact_chat <- function(model, system_prompt = NULL) {
  base_url <- Sys.getenv("CODEAGENT_BASE_URL", "")
  sp <- system_prompt %||% paste0(
    "Summarise the following conversation compactly. ",
    "Preserve key decisions, file paths, errors encountered, ",
    "and conclusions. Output plain text, no headers."
  )
  if (nzchar(base_url)) {
    api_key <- Sys.getenv("CODEAGENT_API_KEY", "")
    ellmer::chat_openai_compatible(
      base_url      = base_url,
      model         = model,
      credentials   = function() api_key,
      system_prompt = sp
    )
  } else {
    ellmer::chat_anthropic(model = model, system_prompt = sp)
  }
}

# Resolve which model to use for compaction/summarisation. Prefers an explicitly
# configured small/fast model, else reuses the MAIN chat's own model (guaranteed
# to exist on whatever gateway is in use), and only falls back to the Anthropic
# .HAIKU_MODEL literal as a last resort. This fixes /compact on OpenAI-compatible
# gateways (e.g. Databricks) where "claude-haiku-4-5-*" is not a valid model id.
.resolve_compact_model <- function(chat = NULL, settings = list()) {
  settings$small_fast_model %||%
    getOption("codeagent.small_fast_model", NULL) %||%
    tryCatch(chat$get_model(), error = function(e) NULL) %||%
    .HAIKU_MODEL
}

# ---------------------------------------------------------------------------
# Token estimation for ellmer Chat objects
# ---------------------------------------------------------------------------

#' Estimate token count for an ellmer Chat object
#'
#' Uses the char/4 heuristic across all turns.
#'
#' @param chat An `ellmer::Chat` object.
#' @return Integer. Estimated token count.
#' @keywords internal
estimate_tokens <- function(chat) {
  turns <- .safe_get_turns(chat)
  if (length(turns) == 0L) return(0L)
  total_chars <- sum(vapply(turns, function(turn) {
    contents <- tryCatch(turn@contents, error = function(e) list())
    sum(vapply(contents, .content_chars, numeric(1)))
  }, numeric(1)))
  # Use same heuristic as estimate_tokens_text() for consistency
  as.integer(ceiling(total_chars / 3.5))
}

# Character size of a single content block. Counts BOTH text (ContentText@text)
# and tool-result payloads (ContentToolResult@value) -- the old estimate only
# read @text, so tool-heavy contexts (the exact case mid-loop compaction targets)
# were undercounted. A block has one or the other, so summing is safe.
.content_chars <- function(c) {
  txt <- tryCatch(as.character(c@text %||% ""), error = function(e) "")
  val <- tryCatch(as.character(c@value %||% ""), error = function(e) "")
  nchar(txt) + nchar(val)
}

# Real input tokens from the most recent API exchange, via ellmer get_tokens().
# get_tokens() returns one row per assistant response with columns
# input/output/cached_input/cost. The last row's input already includes the
# entire context sent, so input+output approximates the current context size.
.last_usage_tokens <- function(chat) {
  if (is.null(chat) || !("get_tokens" %in% names(chat))) return(NA_integer_)
  tk <- tryCatch(chat$get_tokens(), error = function(e) NULL)
  if (is.null(tk) || !is.data.frame(tk) || nrow(tk) == 0L) return(NA_integer_)
  inp <- suppressWarnings(as.numeric(tk$input))
  out <- suppressWarnings(as.numeric(tk$output))
  cached <- if ("cached_input" %in% names(tk))
    suppressWarnings(as.numeric(tk$cached_input)) else rep(0, nrow(tk))
  last_in <- inp[length(inp)]; if (is.na(last_in)) last_in <- 0
  last_out <- out[length(out)]; if (is.na(last_out)) last_out <- 0
  last_cached <- cached[length(cached)]; if (is.na(last_cached)) last_cached <- 0
  v <- last_in + last_out + last_cached
  if (v > 0) as.integer(v) else NA_integer_
}

#' Token count preferring real usage over the char heuristic
#'
#' Mirrors Claude Code `tokenCountWithEstimation` (src/utils/tokens.ts): use the
#' real token usage from the last API exchange when available, otherwise fall
#' back to the char/3.5 estimate. This makes the compaction trigger fire on
#' actual model token counts rather than a rough character approximation.
#'
#' @param chat An `ellmer::Chat` object.
#' @param allow_network Logical. If `TRUE`, explicitly call
#'   `chat$token_count(include = "complete")`; defaults to `FALSE` so UI and
#'   compaction paths never perform implicit token-count HTTP requests.
#' @return Integer token count.
#' @keywords internal
token_count_with_estimation <- function(chat, allow_network = FALSE) {
  if (isTRUE(allow_network) && !is.null(chat) &&
      is.function(tryCatch(chat$token_count, error = function(e) NULL))) {
    exact <- tryCatch(chat$token_count(include = "complete"),
                      error = function(e) NA_real_)
    exact <- suppressWarnings(as.numeric(exact)[1L])
    if (length(exact) && !is.na(exact) && exact >= 0) return(as.integer(exact))
  }
  real <- tryCatch(.last_usage_tokens(chat), error = function(e) NA_integer_)
  if (!is.na(real) && real > 0L) return(real)
  estimate_tokens(chat)
}

# Char/3.5 token estimate for a bare list of turns. Used by PTL head-dropping
# and on_request_start(), where the list includes the pending outgoing turn.
.estimate_turns_tokens <- function(turns) {
  if (length(turns) == 0L) return(0L)
  total_chars <- sum(vapply(turns, function(turn) {
    contents <- tryCatch(turn@contents, error = function(e) list())
    sum(vapply(contents, .content_chars, numeric(1)))
  }, numeric(1)))
  as.integer(ceiling(total_chars / 3.5))
}

# Parse provider PTL usage without retaining the raw error text. Returns actual
# and limit as integers when available.
.parse_ptl_usage <- function(msg) {
  out <- list(actual = NA_integer_, limit = NA_integer_)
  if (is.null(msg) || !length(msg) || !nzchar(msg[[1L]])) return(out)
  text <- as.character(msg[[1L]])
  number <- function(x) {
    value <- suppressWarnings(as.integer(gsub(",", "", x, fixed = TRUE)))
    if (!length(value) || is.na(value) || value < 10000L) NA_integer_ else value
  }

  pair <- regexec(
    "([0-9][0-9,]{3,})[[:space:]]*(?:tokens?)?[[:space:]]*>[[:space:]]*([0-9][0-9,]{3,})",
    text,
    perl = TRUE,
    ignore.case = TRUE
  )
  match <- regmatches(text, pair)[[1L]]
  if (length(match) == 3L) {
    out$actual <- number(match[[2L]])
    out$limit <- number(match[[3L]])
    return(out)
  }

  limit_pattern <- paste0(
    "(?:maximum context length is|context limit(?: is|:)?|maximum(?: is|:)?)",
    "[[:space:]]*([0-9][0-9,]{3,})"
  )
  limit_match <- regexec(
    limit_pattern,
    text,
    perl = TRUE,
    ignore.case = TRUE
  )
  match <- regmatches(text, limit_match)[[1L]]
  if (length(match) == 2L) {
    out$limit <- number(match[[2L]])
    return(out)
  }

  nums <- regmatches(text, gregexpr("[0-9][0-9,]{3,}", text))[[1L]]
  values <- vapply(nums, number, integer(1L))
  values <- values[!is.na(values)]
  if (length(values) == 1L) out$limit <- values[[1L]]
  if (length(values) >= 2L) {
    out$actual <- max(values)
    out$limit <- min(values)
  }
  out
}

.parse_ptl_limit <- function(msg) {
  .parse_ptl_usage(msg)$limit
}

# Placeholder text injected by L1 compaction
.SNIP_PLACEHOLDER <- "[Old tool result content cleared]"

# ---------------------------------------------------------------------------
# Outgoing request snapshots
# ---------------------------------------------------------------------------

.persisted_request_turns <- function(chat) {
  tryCatch(
    chat$get_turns(include_system_prompt = TRUE),
    error = function(e) .safe_get_turns(chat)
  )
}

.build_outgoing_snapshot <- function(chat, request_turns = NULL,
                                     pending_turn = NULL,
                                     use_provider_usage = FALSE) {
  if (!is.null(request_turns)) {
    turns <- request_turns
    if (is.null(pending_turn) && length(turns) > 0L)
      pending_turn <- turns[[length(turns)]]
  } else {
    turns <- .persisted_request_turns(chat)
    if (!is.null(pending_turn)) turns <- c(turns, list(pending_turn))
  }

  structural_tokens <- tryCatch(
    .estimate_turns_tokens(turns),
    error = function(e) 0L
  )
  tokens <- structural_tokens
  provider_tokens <- NA_integer_
  if (isTRUE(use_provider_usage)) {
    provider_tokens <- tryCatch(
      .last_usage_tokens(chat),
      error = function(e) NA_integer_
    )
    if (!is.na(provider_tokens))
      tokens <- max(tokens, provider_tokens)
  }

  list(
    turns = turns,
    pending_turn = pending_turn,
    structural_tokens = as.integer(structural_tokens),
    provider_tokens = as.integer(provider_tokens),
    tokens = as.integer(tokens)
  )
}

# ---------------------------------------------------------------------------
# L1: MicroCompact / Snip
# ---------------------------------------------------------------------------

#' L1: Replace old tool results with a placeholder
#'
#' Keeps the `keep_recent_turns` most recent turns intact and replaces
#' large tool results in earlier turns with a short placeholder.
#'
#' @param chat An `ellmer::Chat` object (modified in place via set_turns).
#' @param keep_recent_turns Integer. Number of recent turns to leave untouched.
#' @param min_chars Integer. Only replace results larger than this size.
#' @return Invisibly NULL.
#' @keywords internal
snip_old_tools <- function(chat, keep_recent_turns = 10L, min_chars = 500L,
                           target_tokens = NULL) {
  turns <- .safe_get_turns(chat)
  if (length(turns) <= keep_recent_turns) return(invisible(FALSE))

  cutoff <- length(turns) - keep_recent_turns
  modified <- FALSE

  for (i in seq_len(cutoff)) {
    # Budget-aware micro-compaction (Claude Code clears oldest tool results
    # until the tool-result payload is under a token budget). When no budget is
    # given, clear all eligible old tool results (legacy behaviour).
    if (!is.null(target_tokens) &&
        .tool_result_tokens(turns) <= as.numeric(target_tokens)) break
    turn <- turns[[i]]
    contents <- tryCatch(turn@contents, error = function(e) NULL)
    if (is.null(contents)) next
    new_contents <- lapply(contents, function(c) {
      # Replace large ToolResultBlock content
      is_tool_result <- tryCatch(
        inherits(c, "ellmer::ContentToolResult") ||
          identical(class(c)[[1L]], "ContentToolResult"),
        error = function(e) FALSE
      )
      if (!is_tool_result) return(c)
      txt <- tryCatch(c@value %||% "", error = function(e) "")
      if (nchar(as.character(txt)) < min_chars) return(c)
      tryCatch({
        c@value <- .SNIP_PLACEHOLDER
        modified <<- TRUE
      }, error = function(e) NULL)
      c
    })
    tryCatch(turns[[i]]@contents <- new_contents, error = function(e) NULL)
  }

  if (modified) {
    tryCatch(chat$set_turns(turns), error = function(e) NULL)
  }
  invisible(modified)
}

# Approximate tool-result payload tokens (chars/3.5) across a turns list. Used
# for budget-aware micro-compaction; measures exactly what snip_old_tools clears
# (ToolResult@value), so it drops as results are snipped -- unlike estimate_tokens
# which only counts text content.
.tool_result_tokens <- function(turns) {
  is_tr <- function(c) tryCatch(
    inherits(c, "ellmer::ContentToolResult") ||
      identical(class(c)[[1L]], "ContentToolResult"),
    error = function(e) FALSE)
  total <- 0
  for (t in turns) {
    contents <- tryCatch(t@contents, error = function(e) list())
    for (c in contents) {
      if (is_tr(c)) {
        v <- tryCatch(as.character(c@value %||% ""), error = function(e) "")
        total <- total + nchar(v)
      }
    }
  }
  as.integer(ceiling(total / 3.5))
}

# ---------------------------------------------------------------------------
# Mid-loop compaction (before every model request)
# ---------------------------------------------------------------------------
# codeagent also checks compaction at turn boundaries before chat$chat().
# ellmer's on_request_start callback (tidyverse/ellmer#1052) closes the timing
# gap for a single turn with many tool rounds: it fires before every request and
# supplies the complete outgoing request, including the pending turn, for
# threshold accounting. The pending turn is inspected for size; history is
# rewritten only through get_turns()/set_turns(), matching ellmer's contract.
# Two tiers mirror the turn-boundary flow:
#   * default     -> cheap budget-aware micro snip (no LLM), snip_old_tools().
#   * opt-in full -> session_memory_compact() then full_compact() fallback.

# Micro snip on by default (matches Claude Code default-on compaction; cheap +
# safe, only acts near the context limit). Toggle: settings$midloop_compact /
# options(codeagent.midloop_compact).
.midloop_enabled <- function(settings = list()) {
  isTRUE(settings$midloop_compact) ||
    isTRUE(getOption("codeagent.midloop_compact", FALSE))
}

# Opt-in: also run the full two-level compact (LLM summary) mid-loop when a snip
# is not enough. Off by default because it makes a blocking model call mid-stream.
.midloop_full_enabled <- function(settings = list()) {
  isTRUE(settings$midloop_full_compact) ||
    isTRUE(getOption("codeagent.midloop_full_compact", FALSE))
}

# Trigger token count. Explicit override lets callers fire earlier; otherwise
# resolve the threshold from the model, provider capability, and optional raw
# context-window override using the same output reserve and 13K buffer.
.midloop_trigger <- function(settings = list(), model = "", chat = NULL) {
  threshold <- settings$midloop_threshold %||%
    getOption("codeagent.midloop_threshold", NA_integer_)
  if (!is.na(threshold) && as.numeric(threshold) > 0)
    return(as.integer(threshold))
  .auto_compact_threshold(
    model,
    chat,
    context_window = settings$model_limit %||% NULL
  )
}

# Budget (in tool-result tokens) the micro snip aims to stay under. Default =
# half the same request threshold; override via settings/option.
.midloop_snip_target <- function(settings = list(), model = "", chat = NULL) {
  target <- settings$midloop_snip_target %||%
    getOption("codeagent.midloop_snip_target", NA_integer_)
  if (!is.na(target) && as.numeric(target) > 0) return(as.integer(target))
  as.integer(.midloop_trigger(settings, model, chat) %/% 2L)
}

.new_compaction_decision <- function(action, reason, before_estimate,
                                     after_estimate, threshold, changed,
                                     summary_calls = 0L, success = TRUE,
                                     started_at = proc.time()[["elapsed"]]) {
  duration_ms <- as.integer(round(
    (proc.time()[["elapsed"]] - started_at) * 1000
  ))
  list(
    action = action,
    reason = reason,
    before_estimate = as.integer(before_estimate),
    after_estimate = as.integer(after_estimate),
    threshold = as.integer(threshold),
    changed = isTRUE(changed),
    summary_calls = as.integer(summary_calls),
    duration_ms = max(0L, duration_ms),
    success = isTRUE(success)
  )
}

.adaptive_compact_pipeline <- function(chat, settings = list(), model = "",
                                       compact_model = .HAIKU_MODEL,
                                       request_turns = NULL,
                                       full_enabled = FALSE,
                                       force_summary = FALSE,
                                       use_provider_usage = TRUE) {
  started_at <- proc.time()[["elapsed"]]
  initial <- .build_outgoing_snapshot(
    chat,
    request_turns = request_turns,
    use_provider_usage = use_provider_usage
  )
  threshold <- .midloop_trigger(settings, model, chat)
  before <- initial$tokens
  pending <- initial$pending_turn
  if (!.validate_compaction_structure(initial$turns)$valid) {
    return(.new_compaction_decision(
      "failed", "invalid_structure", before, before, threshold,
      changed = FALSE, success = FALSE, started_at = started_at
    ))
  }

  if (!isTRUE(force_summary) && before < threshold) {
    return(.new_compaction_decision(
      "none", "below_threshold", before, before, threshold,
      changed = FALSE, started_at = started_at
    ))
  }

  keep <- as.integer(settings$midloop_keep_recent %||%
                       getOption("codeagent.midloop_keep_recent", 10L))
  target <- .midloop_snip_target(settings, model, chat)
  did_snip <- isTRUE(snip_old_tools(
    chat,
    keep_recent_turns = keep,
    target_tokens = target
  ))
  current <- if (did_snip) {
    .build_outgoing_snapshot(
      chat,
      pending_turn = pending,
      use_provider_usage = FALSE
    )
  } else {
    initial
  }
  if (!.validate_compaction_structure(current$turns)$valid) {
    return(.new_compaction_decision(
      if (did_snip) "micro_snip" else "failed",
      "invalid_structure", before, current$tokens, threshold,
      changed = did_snip, success = FALSE, started_at = started_at
    ))
  }

  if (!isTRUE(force_summary) && current$tokens < threshold) {
    return(.new_compaction_decision(
      if (did_snip) "micro_snip" else "none",
      "cheap_reduction_sufficient",
      before,
      current$tokens,
      threshold,
      changed = did_snip,
      started_at = started_at
    ))
  }

  if (!isTRUE(full_enabled) && !isTRUE(force_summary)) {
    return(.new_compaction_decision(
      if (did_snip) "micro_snip" else "none",
      "over_threshold_full_disabled",
      before,
      current$tokens,
      threshold,
      changed = did_snip,
      success = FALSE,
      started_at = started_at
    ))
  }

  summary_calls <- 0L
  did_incremental <- isTRUE(session_memory_compact(
    chat,
    model = compact_model,
    pending_turn = pending
  ))
  if (did_incremental) {
    summary_calls <- summary_calls + 1L
    current <- .build_outgoing_snapshot(
      chat,
      pending_turn = pending,
      use_provider_usage = FALSE
    )
    if (!.validate_compaction_structure(current$turns)$valid) {
      return(.new_compaction_decision(
        "incremental_summary", "invalid_structure", before,
        current$tokens, threshold, changed = TRUE,
        summary_calls = summary_calls, success = FALSE,
        started_at = started_at
      ))
    }
    if (current$tokens < threshold) {
      return(.new_compaction_decision(
        "incremental_summary",
        "summary_sufficient",
        before,
        current$tokens,
        threshold,
        changed = TRUE,
        summary_calls = summary_calls,
        started_at = started_at
      ))
    }
  }

  did_full <- isTRUE(full_compact(
    chat,
    model = compact_model,
    pending_turn = pending
  ))
  if (did_full) summary_calls <- summary_calls + 1L
  current <- .build_outgoing_snapshot(
    chat,
    pending_turn = pending,
    use_provider_usage = FALSE
  )
  if (!.validate_compaction_structure(current$turns)$valid) {
    return(.new_compaction_decision(
      if (did_full) "full_summary" else "failed",
      "invalid_structure", before, current$tokens, threshold,
      changed = did_incremental || did_full,
      summary_calls = summary_calls, success = FALSE,
      started_at = started_at
    ))
  }

  if (did_full && current$tokens < threshold) {
    return(.new_compaction_decision(
      "full_summary",
      "summary_sufficient",
      before,
      current$tokens,
      threshold,
      changed = TRUE,
      summary_calls = summary_calls,
      started_at = started_at
    ))
  }

  if (did_incremental || did_full) {
    return(.new_compaction_decision(
      if (did_full) "full_summary" else "incremental_summary",
      "post_compact_still_large",
      before,
      current$tokens,
      threshold,
      changed = TRUE,
      summary_calls = summary_calls,
      success = FALSE,
      started_at = started_at
    ))
  }

  .new_compaction_decision(
    if (did_snip) "micro_snip" else "none",
    "summary_unavailable",
    before,
    current$tokens,
    threshold,
    changed = did_snip,
    summary_calls = summary_calls,
    success = FALSE,
    started_at = started_at
  )
}

# Compact mid-loop if enabled AND over threshold. The logical return preserves
# compatibility; a sanitized structured decision is attached as an attribute.
.midloop_compact_step <- function(chat, settings = list(), ctrl = NULL,
                                  model = "", compact_model = .HAIKU_MODEL,
                                  request_turns = NULL) {
  if (!.midloop_enabled(settings)) return(invisible(FALSE))

  decision <- tryCatch({
    if (!is.null(ctrl) && is.function(ctrl$adaptive_compact)) {
      ctrl$adaptive_compact(
        chat,
        settings = settings,
        model = model,
        compact_model = compact_model,
        request_turns = request_turns,
        full_enabled = .midloop_full_enabled(settings),
        hooks = settings$hooks_registry %||% NULL
      )
    } else {
      .adaptive_compact_pipeline(
        chat,
        settings = settings,
        model = model,
        compact_model = compact_model,
        request_turns = request_turns,
        full_enabled = .midloop_full_enabled(settings)
      )
    }
  }, error = function(e) {
    snapshot <- .build_outgoing_snapshot(
      chat,
      request_turns = request_turns,
      use_provider_usage = TRUE
    )
    .new_compaction_decision(
      "failed", "callback_error", snapshot$tokens, snapshot$tokens,
      .midloop_trigger(settings, model, chat),
      changed = FALSE, success = FALSE
    )
  })

  if (decision$action %in% c(
      "micro_snip", "incremental_summary", "full_summary")) {
    message(sprintf(
      "[codeagent] mid-loop %s (tokens~%d -> %d)",
      decision$action,
      decision$before_estimate,
      decision$after_estimate
    ))
  }
  acted <- isTRUE(decision$changed)
  attr(acted, "decision") <- decision
  invisible(acted)
}

#' Register per-request mid-loop compaction on a Chat
#'
#' Adds an `on_request_start` callback that checks context before every model
#' request, including every tool-loop round. Default = budget-aware micro snip
#' (cheap, no LLM); opt in to a full two-level compact mid-loop with
#' `settings$midloop_full_compact`. The whole feature is gated by
#' `settings$midloop_compact` / `options(codeagent.midloop_compact = TRUE)`
#' (on by default via settings).
#'
#' @param chat An `ellmer::Chat` object.
#' @param settings Named list from [load_settings()].
#' @return Invisibly `chat`.
#' @keywords internal
register_midloop_compaction <- function(chat, settings = list()) {
  force(chat)
  force(settings)
  # Install at most once per chat: .register_all_tools may run several times on
  # the same chat during Shiny tool re-registration, while ellmer callbacks
  # accumulate.
  if (!.chat_once(chat, "midloop")) return(invisible(chat))
  ctrl          <- tryCatch(CompactionController$new(), error = function(e) NULL)
  model         <- settings$model %||% ""
  compact_model <- settings$compact_model %||% settings$small_fast_model %||%
    .HAIKU_MODEL
  tryCatch(
    chat$on_request_start(function(turns) {
      if (length(turns) > 0L)
        attr(chat, "codeagent_pending_request_turn") <- turns[[length(turns)]]
      tryCatch(
        .midloop_compact_step(
          chat,
          settings,
          ctrl,
          model,
          compact_model,
          request_turns = turns
        ),
        error = function(e) NULL
      )
      invisible(NULL)
    }),
    error = function(e) NULL
  )
  tryCatch(
    chat$on_request_end(function(turn) {
      attr(chat, "codeagent_pending_request_turn") <- NULL
      invisible(NULL)
    }),
    error = function(e) NULL
  )
  invisible(chat)
}

# ---------------------------------------------------------------------------
# Structured serialization for compaction summaries
# ---------------------------------------------------------------------------

.compact_content_type <- function(content) {
  cls <- tryCatch(class(content)[[1L]], error = function(e) "unknown")
  sub("^.*::", "", cls)
}

.compact_json <- function(x) {
  tryCatch(
    as.character(jsonlite::toJSON(
      x,
      auto_unbox = TRUE,
      null = "null",
      na = "null",
      digits = NA
    )),
    error = function(e) "[unserializable]"
  )
}

.compact_bound_text <- function(text, max_chars) {
  text <- paste(as.character(text %||% ""), collapse = "\n")
  max_chars <- max(0L, as.integer(max_chars))
  if (nchar(text) <= max_chars) return(text)
  if (max_chars == 0L) return("")

  marker <- "\n[... block truncated ...]\n"
  if (max_chars <= nchar(marker) + 2L)
    return(substr(text, 1L, max_chars))

  available <- max_chars - nchar(marker)
  head_n <- as.integer(ceiling(available * 2 / 3))
  tail_n <- available - head_n
  tail_start <- max(1L, nchar(text) - tail_n + 1L)
  paste0(
    substr(text, 1L, head_n),
    marker,
    substr(text, tail_start, nchar(text))
  )
}

.serialize_compact_content <- function(content) {
  type <- .compact_content_type(content)

  if (identical(type, "ContentText")) {
    text <- tryCatch(as.character(content@text %||% ""),
                     error = function(e) "")
    return(paste0("TEXT:\n", paste(text, collapse = "\n")))
  }

  if (identical(type, "ContentToolRequest")) {
    id <- tryCatch(as.character(content@id %||% ""),
                   error = function(e) "")
    name <- tryCatch(as.character(content@name %||% ""),
                     error = function(e) "")
    arguments <- tryCatch(content@arguments, error = function(e) list())
    return(paste0(
      "TOOL_REQUEST id=", .compact_json(id),
      " name=", .compact_json(name),
      "\narguments: ", .compact_json(arguments)
    ))
  }

  if (identical(type, "ContentToolResult")) {
    request_id <- tryCatch(as.character(content@request@id %||% ""),
                           error = function(e) "")
    value <- tryCatch(content@value, error = function(e) NULL)
    value_text <- if (is.character(value)) {
      paste(value, collapse = "\n")
    } else {
      .compact_json(value)
    }
    error <- tryCatch(content@error, error = function(e) NULL)
    error_text <- if (is.null(error)) {
      "none"
    } else if (inherits(error, "condition")) {
      conditionMessage(error)
    } else {
      paste(as.character(error), collapse = "\n")
    }
    return(paste0(
      "TOOL_RESULT request_id=", .compact_json(request_id),
      " error=", .compact_json(error_text),
      "\nvalue: ", value_text
    ))
  }

  if (grepl("Citation|Image|PDF|Media|WebSource", type, ignore.case = TRUE))
    return(paste0("MEDIA type=", .compact_json(type), " [content omitted]"))

  paste0("CONTENT type=", .compact_json(type), " [unsupported block omitted]")
}

.serialize_compact_turn <- function(turn, index) {
  role <- tryCatch(as.character(turn@role %||% "unknown"),
                   error = function(e) "unknown")
  contents <- tryCatch(turn@contents, error = function(e) list())
  blocks <- vapply(contents, .serialize_compact_content, character(1L))
  paste0(
    "TURN ", as.integer(index), "\n",
    "ROLE: ", role, "\n",
    paste(blocks, collapse = "\n")
  )
}

.compact_bound_turns <- function(parts, max_chars) {
  max_chars <- max(0L, as.integer(max_chars))
  if (length(parts) == 0L || max_chars == 0L) return("")

  full <- paste(parts, collapse = "\n\n")
  if (nchar(full) <= max_chars) return(full)
  if (length(parts) == 1L) return(.compact_bound_text(parts[[1L]], max_chars))

  marker <- "\n\n[... serialization truncated; middle turns omitted ...]\n\n"
  if (max_chars <= nchar(marker) + 2L)
    return(substr(full, 1L, max_chars))

  available <- max_chars - nchar(marker)
  head_budget <- as.integer(floor(available * 0.35))
  tail_budget <- available - head_budget
  head <- .compact_bound_text(parts[[1L]], head_budget)
  tail <- .compact_bound_text(parts[[length(parts)]], tail_budget)
  out <- paste0(head, marker, tail)
  substr(out, 1L, max_chars)
}

.serialize_compact_turns <- function(turns, max_chars = Inf) {
  if (length(turns) == 0L) return("")
  parts <- vapply(
    seq_along(turns),
    function(i) .serialize_compact_turn(turns[[i]], i),
    character(1L)
  )
  if (is.infinite(max_chars)) return(paste(parts, collapse = "\n\n"))
  .compact_bound_turns(parts, max_chars)
}

# ---------------------------------------------------------------------------
# L2: Session Memory Compaction (incremental summary)
# ---------------------------------------------------------------------------

# Character size of a whole turn (sum of its content blocks).
.turn_chars <- function(turn) {
  contents <- tryCatch(turn@contents, error = function(e) list())
  sum(vapply(contents, .content_chars, numeric(1)))
}

# TRUE if a turn carries any non-empty text content.
.turn_has_text <- function(turn) {
  contents <- tryCatch(turn@contents, error = function(e) list())
  for (c in contents) {
    txt <- tryCatch(as.character(c@text %||% ""), error = function(e) "")
    if (nzchar(txt)) return(TRUE)
  }
  FALSE
}

# Number of most-recent turns to keep during session-memory compaction, using a
# token budget (Claude Code calculateMessagesToKeepIndex): expand backwards from
# the newest turn until we've retained >= min_tokens AND >= min_text_msgs
# text-bearing turns, capped at max_tokens. Guarantees >= min_text_msgs kept
# when possible, and never keeps everything (leaves >= 2 to summarise upstream).
.session_keep_count <- function(turns, min_tokens = .COMPACT_L2_MIN_TOKENS,
                                min_text_msgs = 5L,
                                max_tokens = .COMPACT_L2_MAX_TOKENS) {
  n <- length(turns)
  if (n == 0L) return(0L)
  tok <- 0
  text_msgs <- 0L
  keep <- 0L
  for (i in rev(seq_len(n))) {
    tok <- tok + .turn_chars(turns[[i]]) / 3.5
    if (.turn_has_text(turns[[i]])) text_msgs <- text_msgs + 1L
    keep <- keep + 1L
    if (tok >= max_tokens) break
    if (tok >= min_tokens && text_msgs >= min_text_msgs) break
  }
  # Never keep everything; leave room to summarise at least a couple of turns.
  max(0L, min(keep, n - 2L))
}

.safe_session_summary_index <- function(turns, desired_index) {
  n <- length(turns)
  desired_index <- max(0L, min(as.integer(desired_index), n))
  if (n < 2L || desired_index == 0L) return(desired_index)

  groups <- .group_compaction_rounds(turns)
  if (length(groups) <= 1L) return(0L)
  boundaries <- cumsum(vapply(groups, length, integer(1L)))
  boundaries <- boundaries[boundaries < n & boundaries >= 2L]
  if (length(boundaries) == 0L) return(0L)
  at_or_after <- boundaries[boundaries >= desired_index]
  if (length(at_or_after)) return(as.integer(min(at_or_after)))
  as.integer(max(boundaries))
}

#' L2: Incremental session memory compaction
#'
#' Summarises early turns while retaining recent context.
#' Keeps between `min_tokens` and `max_tokens` in the summary.
#'
#' @param chat An `ellmer::Chat` object.
#' @param model Character. Haiku model for summarisation.
#' @param min_messages Integer. Minimum number of text messages to keep.
#' @param min_tokens Integer. Minimum tokens to retain.
#' @param max_tokens Integer. Maximum tokens for the summary section.
#' @param pending_turn Optional outgoing pending turn used for pairing validation.
#' @return Invisibly TRUE after a validated history write, otherwise NULL.
#' @keywords internal
session_memory_compact <- function(chat,
                                    model        = .HAIKU_MODEL,
                                    min_messages = 5L,
                                    min_tokens   = .COMPACT_L2_MIN_TOKENS,
                                    max_tokens   = .COMPACT_L2_MAX_TOKENS,
                                    pending_turn = NULL) {
  turns <- .safe_get_turns(chat)
  if (length(turns) < min_messages * 2L) return(invisible(NULL))

  # Preserve model-visible structured content (including tool request/result
  # blocks) while excluding UI-only metadata. Bounding retains both early
  # context and the latest active part of the summarized range.
  n_keep <- .session_keep_count(turns, min_tokens, min_messages, max_tokens)
  n_summ <- .safe_session_summary_index(turns, length(turns) - n_keep)
  if (n_summ < 2L) return(invisible(NULL))

  to_summarise <- .serialize_compact_turns(
    turns[seq_len(n_summ)],
    max_chars = as.integer(max_tokens * 4L)
  )
  if (nchar(to_summarise) < min_tokens * 4L) return(invisible(NULL))

  summary_text <- tryCatch({
    summariser <- .make_compact_chat(model)
    summariser$chat(to_summarise)
  }, error = function(e) {
    # Re-raise so the outer maybe_compact() tryCatch increments the circuit
    # breaker failure counter.  Swallowing the error with warning()+NULL would
    # leave private$failures permanently 0 and the circuit breaker never trips.
    stop("L2 compaction API call failed: ", conditionMessage(e), call. = FALSE)
  })
  if (is.null(summary_text)) return(invisible(NULL))

  # Replace summarised turns with a single system-like summary turn
  summary_turn <- tryCatch({
    ellmer::Turn("user",
                  list(ellmer::ContentText(paste0(
                    "[Session Memory Summary]\n", summary_text
                  ))))
  }, error = function(e) NULL)
  if (is.null(summary_turn)) return(invisible(NULL))

  new_turns <- c(list(summary_turn), turns[(n_summ + 1L):length(turns)])
  validation_turns <- c(
    new_turns,
    if (is.null(pending_turn)) list() else list(pending_turn)
  )
  if (!.validate_compaction_structure(validation_turns)$valid)
    return(invisible(NULL))
  set_ok <- tryCatch({
    chat$set_turns(new_turns)
    TRUE
  }, error = function(e) FALSE)
  if (!set_ok) return(invisible(NULL))
  invisible(TRUE)
}

# ---------------------------------------------------------------------------
# L3: Full Compaction (fork agent, 9-section summary)
# ---------------------------------------------------------------------------

# Verbatim Claude Code compaction prompt (src/services/compact/prompt.ts:22
# NO_TOOLS_PREAMBLE + prompt.ts:61 BASE_COMPACT_PROMPT, with prompt.ts:39
# DETAILED_ANALYSIS_INSTRUCTION_BASE embedded). Transcribed ASCII-only (em-dash
# -> "--"). Kept as a raw string so the text stays byte-for-byte aligned.
# PINNED to Claude Code prompt structure with the 9 summary sections below
# (Primary Request/Intent ... Optional Next Step). test-compaction-cc.R guards
# against accidental drift of these section headers. Re-verify when tracking a
# newer Claude Code release (CC is closed-source and this prompt can evolve).
.COMPACT_SYSTEM_PROMPT <- r"---(CRITICAL: Respond with TEXT ONLY. Do NOT call any tools.

- Do NOT use Read, Bash, Grep, Glob, Edit, Write, or ANY other tool.
- You already have all the context you need in the conversation above.
- Tool calls will be REJECTED and will waste your only turn -- you will fail the task.
- Your entire response must be plain text: an <analysis> block followed by a <summary> block.

Your task is to create a detailed summary of the conversation so far, paying close attention to the user's explicit requests and your previous actions.
This summary should be thorough in capturing technical details, code patterns, and architectural decisions that would be essential for continuing development work without losing context.

Before providing your final summary, wrap your analysis in <analysis> tags to organize your thoughts and ensure you've covered all necessary points. In your analysis process:

1. Chronologically analyze each message and section of the conversation. For each section thoroughly identify:
   - The user's explicit requests and intents
   - Your approach to addressing the user's requests
   - Key decisions, technical concepts and code patterns
   - Specific details like:
     - file names
     - full code snippets
     - function signatures
     - file edits
   - Errors that you ran into and how you fixed them
   - Pay special attention to specific user feedback that you received, especially if the user told you to do something differently.
2. Double-check for technical accuracy and completeness, addressing each required element thoroughly.

Your summary should include the following sections:

1. Primary Request and Intent: Capture all of the user's explicit requests and intents in detail
2. Key Technical Concepts: List all important technical concepts, technologies, and frameworks discussed.
3. Files and Code Sections: Enumerate specific files and code sections examined, modified, or created. Pay special attention to the most recent messages and include full code snippets where applicable and include a summary of why this file read or edit is important.
4. Errors and fixes: List all errors that you ran into, and how you fixed them. Pay special attention to specific user feedback that you received, especially if the user told you to do something differently.
5. Problem Solving: Document problems solved and any ongoing troubleshooting efforts.
6. All user messages: List ALL user messages that are not tool results. These are critical for understanding the users' feedback and changing intent.
7. Pending Tasks: Outline any pending tasks that you have explicitly been asked to work on.
8. Current Work: Describe in detail precisely what was being worked on immediately before this summary request, paying special attention to the most recent messages from both user and assistant. Include file names and code snippets where applicable.
9. Optional Next Step: List the next step that you will take that is related to the most recent work you were doing. IMPORTANT: ensure that this step is DIRECTLY in line with the user's most recent explicit requests, and the task you were working on immediately before this summary request. If your last task was concluded, then only list next steps if they are explicitly in line with the users request. Do not start on tangential requests or really old requests that were already completed without confirming with the user first.
                       If there is a next step, include direct quotes from the most recent conversation showing exactly what task you were working on and where you left off. This should be verbatim to ensure there's no drift in task interpretation.

Here's an example of how your output should be structured:

<example>
<analysis>
[Your thought process, ensuring all points are covered thoroughly and accurately]
</analysis>

<summary>
1. Primary Request and Intent:
   [Detailed description]

2. Key Technical Concepts:
   - [Concept 1]
   - [Concept 2]
   - [...]

3. Files and Code Sections:
   - [File Name 1]
      - [Summary of why this file is important]
      - [Summary of the changes made to this file, if any]
      - [Important Code Snippet]
   - [File Name 2]
      - [Important Code Snippet]
   - [...]

4. Errors and fixes:
    - [Detailed description of error 1]:
      - [How you fixed the error]
      - [User feedback on the error if any]
    - [...]

5. Problem Solving:
   [Description of solved problems and ongoing troubleshooting]

6. All user messages:
    - [Detailed non tool use user message]
    - [...]

7. Pending Tasks:
   - [Task 1]
   - [Task 2]
   - [...]

8. Current Work:
   [Precise description of current work]

9. Optional Next Step:
   [Optional Next step to take]

</summary>
</example>

Please provide your summary based on the conversation so far, following this structure and ensuring precision and thoroughness in your response.

There may be additional summarization instructions provided in the included context. If so, remember to follow these instructions when creating the above summary. Examples of instructions include:
<example>
## Compact Instructions
When summarizing the conversation focus on typescript code changes and also remember the mistakes you made and how you fixed them.
</example>

<example>
# Summary instructions
When you are using compact - please focus on test output and code changes. Include file reads verbatim.
</example>
)---"

# Legacy alias kept so any external reference still resolves; prefer
# .COMPACT_SYSTEM_PROMPT.
.FULL_COMPACT_SYSTEM <- .COMPACT_SYSTEM_PROMPT

# Extract the <summary> block, dropping the <analysis> scratch pad
# (= formatCompactSummary, prompt.ts:327). Returns "Summary:\n<body>".
.extract_compact_summary <- function(text) {
  text <- as.character(text %||% "")
  if (grepl("<summary>", text, fixed = TRUE)) {
    body <- sub("(?s).*<summary>(.*?)</summary>.*", "\\1", text, perl = TRUE)
  } else {
    # No tags: drop any <analysis> block, keep the rest.
    body <- sub("(?s)<analysis>.*?</analysis>", "", text, perl = TRUE)
  }
  paste0("Summary:\n", trimws(body))
}

# Build the compaction system prompt, optionally biased by user instructions
# (Claude Code's `/compact <instructions>`). `if` here is fine -- plain function.
.compact_system_prompt <- function(instructions = NULL) {
  if (is.null(instructions) || !nzchar(trimws(as.character(instructions))))
    return(.COMPACT_SYSTEM_PROMPT)
  paste0(.COMPACT_SYSTEM_PROMPT,
         "\n\nADDITIONAL INSTRUCTIONS FROM THE USER for this summary ",
         "(follow these closely when deciding what to keep):\n",
         trimws(as.character(instructions)))
}

# TRUE for a user turn that carries only plain content (no tool request/result),
# i.e. safe to keep verbatim after a full compaction without orphaning a pair.
.is_plain_user_turn <- function(turn) {
  role <- tryCatch(turn@role, error = function(e) "")
  if (!identical(role, "user")) return(FALSE)
  contents <- tryCatch(turn@contents, error = function(e) list())
  for (c in contents) {
    is_tool <- tryCatch(
      inherits(c, "ellmer::ContentToolResult") ||
        inherits(c, "ellmer::ContentToolRequest") ||
        grepl("ContentTool", class(c)[[1L]], fixed = TRUE),
      error = function(e) FALSE)
    if (isTRUE(is_tool)) return(FALSE)
  }
  TRUE
}

# Turns to keep after a full compaction: the summary, plus the most recent plain
# user turn (the current task) when safe. Mirrors Claude Code continuing the
# current work after summarising.
.full_compact_turns <- function(turns, summary_turn) {
  if (length(turns)) {
    last <- turns[[length(turns)]]
    if (.is_plain_user_turn(last)) return(list(summary_turn, last))
  }
  list(summary_turn)
}

#' L3: Full context compaction via fork agent
#'
#' Spawns a separate haiku chat to generate a 9-section structured summary
#' wrapped in `<summary>` tags, then replaces all turns with that summary.
#'
#' @param chat An `ellmer::Chat` object.
#' @param model Character. Haiku model for compaction.
#' @param instructions Character or NULL. Optional user instructions to bias the summary.
#' @param pending_turn Optional outgoing pending turn used for pairing validation.
#' @return Invisibly TRUE after a validated history write, otherwise NULL.
#' @keywords internal
full_compact <- function(chat, model = .HAIKU_MODEL, instructions = NULL,
                         pending_turn = NULL) {
  turns <- .safe_get_turns(chat)
  if (length(turns) < 4L) return(invisible(NULL))

  # Serialize the complete model-visible conversation, including structured
  # tool traffic. The bounded representation keeps early context and the most
  # recent active task instead of truncating only from the tail.
  conv_text <- .serialize_compact_turns(
    turns,
    max_chars = .COMPACT_FULL_TRUNCATE_CHARS
  )

  summary_text <- tryCatch({
    compactor <- .make_compact_chat(model, system_prompt = .compact_system_prompt(instructions))
    compactor$chat(conv_text)
  }, error = function(e) {
    # Re-raise so the outer maybe_compact() tryCatch increments the circuit
    # breaker failure counter.  Swallowing the error with warning()+NULL would
    # leave private$failures permanently 0 and the circuit breaker never trips.
    stop("L3 compaction API call failed: ", conditionMessage(e), call. = FALSE)
  })
  if (is.null(summary_text)) return(invisible(NULL))

  # Strip the <analysis> scratch pad, keep the <summary> body, prefix "Summary:".
  summary_text <- .extract_compact_summary(summary_text)

  # Replace all turns with the summary
  summary_turn <- tryCatch(
    ellmer::Turn("user",
                  list(ellmer::ContentText(summary_text))),
    error = function(e) NULL
  )
  if (is.null(summary_turn)) return(invisible(NULL))

  # Replace history with the summary, but keep the most recent plain user turn
  # (the current task) when it is safe -- mirrors Claude Code continuing the
  # current work after a summary. Skipped if the last turn carries a tool
  # request/result (avoids orphaning a tool_use/tool_result pair).
  compacted_turns <- .full_compact_turns(turns, summary_turn)
  validation_turns <- c(
    compacted_turns,
    if (is.null(pending_turn)) list() else list(pending_turn)
  )
  if (!.validate_compaction_structure(validation_turns)$valid)
    return(invisible(NULL))
  set_ok <- tryCatch({
    chat$set_turns(compacted_turns)
    TRUE
  }, error = function(e) FALSE)
  if (!set_ok) return(invisible(NULL))
  invisible(TRUE)
}

# ---------------------------------------------------------------------------
# L4: PTL Fallback (drop oldest turns on 413 / prompt_too_long)
# ---------------------------------------------------------------------------

# Pair-safe PTL helpers. These remain internal implementation details; the
# documented recovery entry point is ptl_fallback() below.
.turn_tool_request_ids <- function(turn) {
  contents <- tryCatch(turn@contents, error = function(e) list())
  ids <- vapply(contents, function(content) {
    if (!identical(.compact_content_type(content), "ContentToolRequest"))
      return(NA_character_)
    tryCatch(as.character(content@id %||% ""), error = function(e) "")
  }, character(1L))
  ids[!is.na(ids) & nzchar(ids)]
}

.turn_tool_result_ids <- function(turn) {
  contents <- tryCatch(turn@contents, error = function(e) list())
  ids <- vapply(contents, function(content) {
    if (!identical(.compact_content_type(content), "ContentToolResult"))
      return(NA_character_)
    tryCatch(as.character(content@request@id %||% ""),
             error = function(e) "")
  }, character(1L))
  ids[!is.na(ids) & nzchar(ids)]
}

.validate_compaction_structure <- function(turns) {
  seen_requests <- character(0)
  seen_results <- character(0)
  orphan_results <- character(0)
  for (turn in turns) {
    requests <- .turn_tool_request_ids(turn)
    if (length(requests))
      seen_requests <- unique(c(seen_requests, requests))
    results <- .turn_tool_result_ids(turn)
    if (length(results)) {
      orphan_results <- c(
        orphan_results,
        setdiff(results, seen_requests)
      )
      seen_results <- unique(c(seen_results, results))
    }
  }
  orphan_results <- unique(orphan_results)
  unmatched_requests <- setdiff(seen_requests, seen_results)
  list(
    valid = length(orphan_results) == 0L &&
      length(unmatched_requests) == 0L,
    orphan_result_ids = orphan_results,
    unmatched_request_ids = unmatched_requests
  )
}

.group_compaction_rounds <- function(turns) {
  if (length(turns) == 0L) return(list())
  groups <- list()
  current <- list()
  for (turn in turns) {
    if (.is_plain_user_turn(turn) && length(current) > 0L) {
      groups[[length(groups) + 1L]] <- current
      current <- list()
    }
    current[[length(current) + 1L]] <- turn
  }
  if (length(current) > 0L)
    groups[[length(groups) + 1L]] <- current
  groups
}

.flatten_turn_groups <- function(groups) {
  if (length(groups) == 0L) return(list())
  unlist(groups, recursive = FALSE, use.names = FALSE)
}

#' Pair-safe prompt-too-long fallback
#'
#' Drops complete historical API rounds until the estimated request releases the
#' provider-reported token gap. Without an actual/limit pair, targets a 20%
#' reduction. The newest round and pending turn are always retained.
#' @param chat An `ellmer::Chat` object.
#' @param drop_turns Deprecated compatibility argument; raw turns are never
#'   dropped independently.
#' @param error_msg Character or NULL. Provider PTL message.
#' @param pending_turn Optional pending turn, retained outside persisted history.
#' @return A sanitized internal recovery decision.
#' @keywords internal
ptl_fallback <- function(chat, drop_turns = 3L, error_msg = NULL,
                         pending_turn = NULL) {
  turns <- .safe_get_turns(chat)
  outgoing_before <- c(turns, if (is.null(pending_turn)) list() else list(pending_turn))
  before <- .estimate_turns_tokens(outgoing_before)
  initial_structure <- .validate_compaction_structure(outgoing_before)
  if (!initial_structure$valid) {
    decision <- .new_compaction_decision(
      "failed", "invalid_structure", before, before, before,
      changed = FALSE, success = FALSE
    )
    return(c(decision, list(
      dropped_groups = 0L,
      structure_valid = FALSE,
      target_estimate = before
    )))
  }

  groups <- .group_compaction_rounds(turns)
  if (length(groups) <= 1L) {
    decision <- .new_compaction_decision(
      "failed", "no_safe_group", before, before, before,
      changed = FALSE, success = FALSE
    )
    return(c(decision, list(
      dropped_groups = 0L,
      structure_valid = TRUE,
      target_estimate = before
    )))
  }

  usage <- .parse_ptl_usage(error_msg)
  if (!is.na(usage$actual) && !is.na(usage$limit) &&
      usage$actual > usage$limit) {
    gap <- usage$actual - usage$limit
    target <- max(0L, before - gap)
    reason <- "actual_limit_gap"
  } else {
    target <- as.integer(floor(before * 0.8))
    reason <- "fallback_twenty_percent"
  }

  keep_from <- 1L
  candidate <- turns
  structure <- initial_structure
  while (keep_from < length(groups)) {
    candidate_outgoing <- c(
      candidate,
      if (is.null(pending_turn)) list() else list(pending_turn)
    )
    if (.estimate_turns_tokens(candidate_outgoing) <= target) break

    next_keep <- keep_from + 1L
    next_turns <- .flatten_turn_groups(groups[next_keep:length(groups)])
    next_outgoing <- c(
      next_turns,
      if (is.null(pending_turn)) list() else list(pending_turn)
    )
    next_structure <- .validate_compaction_structure(next_outgoing)
    if (!next_structure$valid) break
    keep_from <- next_keep
    candidate <- next_turns
    structure <- next_structure
  }

  dropped <- keep_from - 1L
  after <- .estimate_turns_tokens(c(
    candidate,
    if (is.null(pending_turn)) list() else list(pending_turn)
  ))
  set_ok <- FALSE
  if (dropped > 0L && structure$valid) {
    set_ok <- tryCatch({
      chat$set_turns(candidate)
      TRUE
    }, error = function(e) FALSE)
  }

  decision <- .new_compaction_decision(
    if (dropped > 0L) "ptl_group_drop" else "failed",
    if (dropped > 0L) reason else "no_safe_group",
    before,
    after,
    target,
    changed = set_ok,
    success = set_ok && structure$valid
  )
  c(decision, list(
    dropped_groups = as.integer(dropped),
    structure_valid = isTRUE(structure$valid),
    target_estimate = as.integer(target)
  ))
}

# ---------------------------------------------------------------------------
# L5: Context Collapse (read-time projection -- replace large tool values inline)
# ---------------------------------------------------------------------------

#' L5: Context collapse via read-time projection
#'
#' Replaces the `value` field of all `ContentToolResult` objects in the
#' conversation with a short summary, collapsing large tool outputs without
#' dropping turns. Unlike L1 (which uses a fixed placeholder), this uses the
#' first `max_chars` characters plus a token estimate notice.
#'
#' Called when token count is critically high and L3 full compaction has
#' already been attempted (or failed). This is the lightest non-destructive
#' option before L4 drop.
#'
#' @param chat An `ellmer::Chat` object.
#' @param max_chars Integer. Max characters to retain per tool result.
#' @return Invisibly NULL.
#' @keywords internal
context_collapse <- function(chat, max_chars = 200L) {
  turns <- .safe_get_turns(chat)
  if (length(turns) == 0L) return(invisible(NULL))
  modified <- FALSE

  new_turns <- lapply(turns, function(turn) {
    contents <- tryCatch(turn@contents, error = function(e) NULL)
    if (is.null(contents)) return(turn)
    new_contents <- lapply(contents, function(c) {
      is_result <- tryCatch(
        inherits(c, "ellmer::ContentToolResult") ||
          identical(class(c)[[1L]], "ContentToolResult"),
        error = function(e) FALSE
      )
      if (!is_result) return(c)
      val <- tryCatch(as.character(c@value %||% ""), error = function(e) "")
      if (nchar(val) <= max_chars) return(c)
      collapsed <- paste0(
        substr(val, 1L, max_chars),
        sprintf("\n[...collapsed %d chars]", nchar(val) - max_chars)
      )
      tryCatch({ c@value <- collapsed; modified <<- TRUE }, error = function(e) NULL)
      c
    })
    tryCatch(turn@contents <- new_contents, error = function(e) NULL)
    turn
  })

  if (modified)
    tryCatch(chat$set_turns(new_turns), error = function(e) NULL)
  invisible(NULL)
}

# ---------------------------------------------------------------------------
# CompactionController R6 class (circuit breaker + level dispatcher)
# ---------------------------------------------------------------------------

#' Context compaction controller
#'
#' Monitors token usage and dispatches the appropriate compaction level.
#' Includes a circuit breaker that silences compaction after 3 consecutive
#' failures to prevent infinite compaction loops.
#'
#' @export
CompactionController <- R6::R6Class(
  "CompactionController",

  private = list(
    failures  = 0L,
    # Threshold margins are read from constants at runtime in maybe_compact()
    l1_margin = 0L,
    l2_margin = 0L,
    l3_margin = 0L
  ),

  public = list(

    #' @description Run adaptive compaction with circuit-breaker protection.
    #' @param chat An `ellmer::Chat` object.
    #' @param settings Named compaction settings.
    #' @param model Character. Active request model.
    #' @param compact_model Character. Model for summary tasks.
    #' @param request_turns Optional complete outgoing request including pending.
    #' @param full_enabled Whether summary escalation is allowed.
    #' @param force_summary Whether to summarize even after cheap reduction.
    #' @param hooks Optional lifecycle registry; receives sanitized metadata only.
    #' @param use_provider_usage Whether initial accounting may include prior usage.
    #' @return A sanitized internal compaction decision.
    adaptive_compact = function(chat, settings = list(), model = "",
                                compact_model = .HAIKU_MODEL,
                                request_turns = NULL,
                                full_enabled = FALSE,
                                force_summary = FALSE,
                                hooks = NULL,
                                use_provider_usage = TRUE) {
      history_before <- .safe_get_turns(chat)
      snapshot <- .build_outgoing_snapshot(
        chat,
        request_turns = request_turns,
        use_provider_usage = use_provider_usage
      )
      threshold <- .midloop_trigger(settings, model, chat)
      if (!auto_compact_enabled()) {
        return(.new_compaction_decision(
          "none", "disabled", snapshot$tokens, snapshot$tokens,
          threshold, changed = FALSE, success = FALSE
        ))
      }
      if (private$failures >= .MAX_CONSECUTIVE_COMPACT_FAILS) {
        return(.new_compaction_decision(
          "none", "circuit_open", snapshot$tokens, snapshot$tokens,
          threshold, changed = FALSE, success = FALSE
        ))
      }

      selected <- isTRUE(force_summary) || snapshot$tokens >= threshold
      if (selected && !is.null(hooks)) {
        tryCatch(
          hooks$run_pre_compact("adaptive", list(
            action = "adaptive",
            reason = if (isTRUE(force_summary)) "manual" else "threshold",
            before_estimate = snapshot$tokens,
            threshold = threshold
          )),
          error = function(e) NULL
        )
      }

      decision <- tryCatch(
        .adaptive_compact_pipeline(
          chat,
          settings = settings,
          model = model,
          compact_model = compact_model,
          request_turns = request_turns,
          full_enabled = full_enabled,
          force_summary = force_summary,
          use_provider_usage = use_provider_usage
        ),
        error = function(e) {
          private$failures <- private$failures + 1L
          warning(
            "[codeagent] Compaction failed (attempt ", private$failures,
            ").",
            call. = FALSE
          )
          history_after <- .safe_get_turns(chat)
          changed <- !identical(history_before, history_after)
          after_snapshot <- .build_outgoing_snapshot(
            chat,
            pending_turn = snapshot$pending_turn,
            use_provider_usage = FALSE
          )
          .new_compaction_decision(
            "failed", "callback_error", snapshot$tokens,
            after_snapshot$tokens, threshold,
            changed = changed, success = FALSE
          )
        }
      )
      if (!identical(decision$reason, "callback_error")) {
        if (!isTRUE(decision$success) && decision$summary_calls > 0L) {
          private$failures <- private$failures + 1L
        } else if (isTRUE(decision$success)) {
          private$failures <- 0L
        }
      }
      if (isTRUE(decision$changed) && !is.null(hooks)) {
        tryCatch(
          hooks$run_post_compact("auto", "", decision),
          error = function(e) NULL
        )
      }
      decision
    },

    #' @description Check token usage and compact if needed.
    #' @param chat An `ellmer::Chat` object.
    #' @param model_limit Integer. Raw model context-window token limit.
    #' @param compact_model Character. Model for compaction tasks.
    #' @param model Character. Active request model used to resolve output reserve.
    #' @param hooks Optional lifecycle registry.
    #' @param use_provider_usage Whether initial accounting may include prior usage.
    #' @return Invisibly the internal compaction decision, or NULL when disabled.
    maybe_compact = function(chat, model_limit = 200000L,
                              compact_model = .HAIKU_MODEL, model = "",
                              hooks = NULL, use_provider_usage = TRUE) {
      if (!auto_compact_enabled()) return(invisible(NULL))
      decision <- self$adaptive_compact(
        chat,
        settings = list(model_limit = model_limit),
        model = model,
        compact_model = compact_model,
        full_enabled = TRUE,
        hooks = hooks,
        use_provider_usage = use_provider_usage
      )
      invisible(decision)
    },

    #' @description Force the adaptive summary chain for manual compaction.
    #' @param chat An `ellmer::Chat` object.
    #' @param compact_model Character. Model for compaction tasks.
    #' @return Invisibly TRUE on a validated change, FALSE otherwise. The
    #'   structured decision is attached as a `decision` attribute.
    compact_now = function(chat, compact_model = .HAIKU_MODEL) {
      if (!auto_compact_enabled()) return(invisible(FALSE))
      decision <- self$adaptive_compact(
        chat,
        settings = list(),
        compact_model = compact_model,
        full_enabled = TRUE,
        force_summary = TRUE
      )
      ok <- isTRUE(decision$changed) && isTRUE(decision$success)
      attr(ok, "decision") <- decision
      invisible(ok)
    },

    #' @description Handle a prompt-too-long (PTL) error by dropping turns.
    #' @param chat An `ellmer::Chat` object.
    #' @param error An error condition or message string (parsed for a real
    #'   context limit when present).
    #' @param pending_turn Optional failed outgoing pending turn.
    handle_ptl_error = function(chat, error = NULL, pending_turn = NULL) {
      msg <- if (inherits(error, "condition")) conditionMessage(error)
             else if (is.character(error)) error
             else NULL
      tryCatch(
        ptl_fallback(chat, error_msg = msg, pending_turn = pending_turn),
        error = function(e) NULL
      )
    },

    #' @description Reset the failure counter (e.g. after a successful turn).
    reset_failures = function() {
      private$failures <- 0L
      invisible(self)
    },

    #' @description Return current failure count.
    failure_count = function() private$failures
  )
)
