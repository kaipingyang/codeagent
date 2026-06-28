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
.make_compact_chat <- function(model, system_prompt = NULL) {
  base_url <- Sys.getenv("CODEAGENT_BASE_URL", "")
  sp <- system_prompt %||% paste0(
    "Summarise the following conversation compactly. ",
    "Preserve key decisions, file paths, errors encountered, ",
    "and conclusions. Output plain text, no headers."
  )
  if (nzchar(base_url)) {
    # On Databricks, swap the Anthropic model name for the OpenAI-compat one
    compat_model <- if (identical(model, .HAIKU_MODEL)) .HAIKU_MODEL_OPENAI_COMPAT else model
    api_key <- Sys.getenv("CODEAGENT_API_KEY", "")
    ellmer::chat_openai_compatible(
      base_url      = base_url,
      model         = compat_model,
      credentials   = function() api_key,
      system_prompt = sp
    )
  } else {
    ellmer::chat_anthropic(model = model, system_prompt = sp)
  }
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
    sum(vapply(contents, function(c) {
      text <- tryCatch(c@text %||% "", error = function(e) "")
      nchar(as.character(text))
    }, numeric(1)))
  }, numeric(1)))
  # Use same heuristic as estimate_tokens_text() for consistency
  as.integer(ceiling(total_chars / 3.5))
}

# Placeholder text injected by L1 compaction
.SNIP_PLACEHOLDER <- "[Old tool result content cleared]"

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
snip_old_tools <- function(chat, keep_recent_turns = 10L, min_chars = 500L) {
  turns <- .safe_get_turns(chat)
  if (length(turns) <= keep_recent_turns) return(invisible(NULL))

  cutoff <- length(turns) - keep_recent_turns
  modified <- FALSE

  for (i in seq_len(cutoff)) {
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
  invisible(NULL)
}

# ---------------------------------------------------------------------------
# L2: Session Memory Compaction (incremental summary)
# ---------------------------------------------------------------------------

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
#' @return Invisibly NULL.
#' @keywords internal
session_memory_compact <- function(chat,
                                    model        = .HAIKU_MODEL,
                                    min_messages = 5L,
                                    min_tokens   = .COMPACT_L2_MIN_TOKENS,
                                    max_tokens   = .COMPACT_L2_MAX_TOKENS) {
  turns <- .safe_get_turns(chat)
  if (length(turns) < min_messages * 2L) return(invisible(NULL))

  # Extract text content from turns for summarisation
  messages_text <- vapply(turns, function(turn) {
    role     <- tryCatch(turn@role, error = function(e) "unknown")
    contents <- tryCatch(turn@contents, error = function(e) list())
    text_parts <- vapply(contents, function(c) {
      tryCatch(as.character(c@text %||% ""), error = function(e) "")
    }, character(1))
    paste0(role, ": ", paste(text_parts[nzchar(text_parts)], collapse = " "))
  }, character(1))

  # Identify how many turns to summarise (keep min_messages recent)
  n_keep   <- min(min_messages, length(turns))
  n_summ   <- length(turns) - n_keep
  if (n_summ < 2L) return(invisible(NULL))

  to_summarise <- paste(messages_text[seq_len(n_summ)], collapse = "\n")
  if (nchar(to_summarise) < min_tokens * 4L) return(invisible(NULL))

  # Cap to max_tokens for the summary request
  if (nchar(to_summarise) > max_tokens * 4L)
    to_summarise <- substr(to_summarise, 1L, max_tokens * 4L)

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
  tryCatch(chat$set_turns(new_turns), error = function(e) NULL)
  invisible(NULL)
}

# ---------------------------------------------------------------------------
# L3: Full Compaction (fork agent, 9-section summary)
# ---------------------------------------------------------------------------

.FULL_COMPACT_SYSTEM <- paste0(
  "You are a context compaction assistant. ",
  "Generate a structured summary of the following conversation using exactly ",
  "these nine sections wrapped in <summary> tags:\n",
  "1. Task\n2. Environment\n3. Progress\n4. Files Changed\n",
  "5. Key Decisions\n6. Errors Encountered\n7. Pending Actions\n",
  "8. Tool Results\n9. Next Steps\n\n",
  "Be concise but complete. Preserve file paths, error messages, ",
  "and code snippets verbatim."
)

#' L3: Full context compaction via fork agent
#'
#' Spawns a separate haiku chat to generate a 9-section structured summary
#' wrapped in `<summary>` tags, then replaces all turns with that summary.
#'
#' @param chat An `ellmer::Chat` object.
#' @param model Character. Haiku model for compaction.
#' @return Invisibly NULL.
#' @keywords internal
full_compact <- function(chat, model = .HAIKU_MODEL) {
  turns <- .safe_get_turns(chat)
  if (length(turns) < 4L) return(invisible(NULL))

  # Build text representation of full conversation
  conv_text <- paste(vapply(turns, function(turn) {
    role     <- tryCatch(turn@role, error = function(e) "unknown")
    contents <- tryCatch(turn@contents, error = function(e) list())
    text_parts <- vapply(contents, function(c) {
      tryCatch(as.character(c@text %||% ""), error = function(e) "")
    }, character(1))
    paste0(toupper(role), ": ", paste(text_parts[nzchar(text_parts)],
                                       collapse = " "))
  }, character(1)), collapse = "\n\n")

  # Limit input size to avoid recursion
  if (nchar(conv_text) > .COMPACT_FULL_TRUNCATE_CHARS)
    conv_text <- paste0(substr(conv_text, 1L, .COMPACT_FULL_TRUNCATE_CHARS),
                        "\n[... truncated for compaction ...]")

  summary_text <- tryCatch({
    compactor <- .make_compact_chat(model, system_prompt = .FULL_COMPACT_SYSTEM)
    compactor$chat(conv_text)
  }, error = function(e) {
    # Re-raise so the outer maybe_compact() tryCatch increments the circuit
    # breaker failure counter.  Swallowing the error with warning()+NULL would
    # leave private$failures permanently 0 and the circuit breaker never trips.
    stop("L3 compaction API call failed: ", conditionMessage(e), call. = FALSE)
  })
  if (is.null(summary_text)) return(invisible(NULL))

  # Ensure summary is wrapped in <summary> tags
  if (!grepl("<summary>", summary_text, fixed = TRUE))
    summary_text <- paste0("<summary>\n", summary_text, "\n</summary>")

  # Replace all turns with the summary
  summary_turn <- tryCatch(
    ellmer::Turn("user",
                  list(ellmer::ContentText(summary_text))),
    error = function(e) NULL
  )
  if (is.null(summary_turn)) return(invisible(NULL))

  tryCatch(chat$set_turns(list(summary_turn)), error = function(e) NULL)
  invisible(NULL)
}

# ---------------------------------------------------------------------------
# L4: PTL Fallback (drop oldest turns on 413 / prompt_too_long)
# ---------------------------------------------------------------------------

#' L4: Prompt-too-long fallback -- drop oldest turns
#'
#' Called when the API returns a 413 / prompt_too_long error.
#' Drops `drop_turns` oldest turns to reduce context size.
#'
#' @param chat An `ellmer::Chat` object.
#' @param drop_turns Integer. Number of turns to drop from the start.
#' @return Invisibly NULL.
#' @keywords internal
ptl_fallback <- function(chat, drop_turns = 3L) {
  turns <- .safe_get_turns(chat)
  if (length(turns) <= drop_turns) return(invisible(NULL))
  new_turns <- turns[(drop_turns + 1L):length(turns)]
  tryCatch(chat$set_turns(new_turns), error = function(e) NULL)
  invisible(NULL)
}

# ---------------------------------------------------------------------------
# L5: Context Collapse (read-time projection — replace large tool values inline)
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

    #' @description Check token usage and compact if needed.
    #' @param chat An `ellmer::Chat` object.
    #' @param model_limit Integer. Model context window token limit.
    #' @param compact_model Character. Model for compaction tasks (haiku).
    #' @return Invisibly NULL.
    maybe_compact = function(chat, model_limit = 200000L,
                              compact_model = .HAIKU_MODEL) {
      # Circuit breaker
      if (private$failures >= .COMPACT_CIRCUIT_BREAKER_LIMIT) return(invisible(NULL))

      threshold <- model_limit - .COMPACT_TRIGGER_MARGIN  # e.g. 167K for 200K model
      n         <- estimate_tokens(chat)
      if (n < threshold) return(invisible(NULL))

      tryCatch({
        if (n < threshold + .COMPACT_L2_MARGIN) {
          snip_old_tools(chat)
        } else if (n < threshold + .COMPACT_L3_MARGIN) {
          session_memory_compact(chat, model = compact_model)
        } else if (n < threshold + .COMPACT_L5_MARGIN) {
          full_compact(chat, model = compact_model)
        } else {
          # L5: context collapse (read-time projection) before L4 drop
          context_collapse(chat)
        }
        private$failures <- 0L
      }, error = function(e) {
        private$failures <- private$failures + 1L
        warning("[codeagent] Compaction failed (attempt ", private$failures,
                "): ", conditionMessage(e), call. = FALSE)
      })
      invisible(NULL)
    },

    #' @description Handle a prompt-too-long (PTL) error by dropping turns.
    #' @param chat An `ellmer::Chat` object.
    handle_ptl_error = function(chat) {
      tryCatch(ptl_fallback(chat), error = function(e) NULL)
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
