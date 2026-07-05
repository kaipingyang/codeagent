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
  last_in  <- inp[length(inp)];  if (is.na(last_in))  last_in  <- 0
  last_out <- out[length(out)];  if (is.na(last_out)) last_out <- 0
  v <- last_in + last_out
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
#' @return Integer token count.
#' @keywords internal
token_count_with_estimation <- function(chat) {
  real <- tryCatch(.last_usage_tokens(chat), error = function(e) NA_integer_)
  if (!is.na(real) && real > 0L) return(real)
  estimate_tokens(chat)
}

# Char/3.5 token estimate for a bare list of turns (used by PTL head-dropping
# where we work on a turns vector before calling set_turns()).
.estimate_turns_tokens <- function(turns) {
  if (length(turns) == 0L) return(0L)
  total_chars <- sum(vapply(turns, function(turn) {
    contents <- tryCatch(turn@contents, error = function(e) list())
    sum(vapply(contents, function(c) {
      nchar(as.character(tryCatch(c@text %||% "", error = function(e) "")))
    }, numeric(1)))
  }, numeric(1)))
  as.integer(ceiling(total_chars / 3.5))
}

# Parse a real context/token limit out of a PTL/413 error message when the
# provider reports one (mirrors Claude Code reading contextLimit in
# withRetry.ts). Returns the largest plausible token limit (>= 10000) or NA.
.parse_ptl_limit <- function(msg) {
  if (is.null(msg) || !length(msg) || !nzchar(msg[[1]])) return(NA_integer_)
  nums <- regmatches(msg, gregexpr("[0-9][0-9,]{3,}", msg))[[1]]
  if (!length(nums)) return(NA_integer_)
  vals <- suppressWarnings(as.integer(gsub(",", "", nums)))
  vals <- vals[!is.na(vals) & vals >= 10000L]
  if (!length(vals)) return(NA_integer_)
  max(vals)
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
# Mid-loop compaction (between tool rounds) -- Plan B
# ---------------------------------------------------------------------------
# codeagent's harness runs compaction at turn boundaries (before chat$chat()).
# A single turn with many large tool outputs can grow the context mid-loop with
# no chance to compact until the turn ends. This uses ellmer's RELEASED
# `on_tool_result` callback (fires between tool rounds, before the next model
# request) to compact when over threshold. Two tiers (mirrors Claude Code
# autoCompactIfNeeded):
#   * default    -> cheap budget-aware micro snip (no LLM), snip_old_tools().
#   * opt-in full -> the same two-level compact as the turn boundary
#                    (session_memory -> full), via CompactionController.
# The cleaner target is upstream `on_turn_start` (PR tidyverse/ellmer#1052),
# which fires before EVERY model request (not just between tool rounds);
# see references/plan/13-mid-loop-compaction.md. NB `on_tool_request` cannot
# substitute: it fires AFTER the model request (inside invoke_tools) and only
# when the model called tools, so it is not a pre-request compaction hook.

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

# Trigger token count. Explicit override (settings$midloop_threshold / option)
# lets it fire earlier than turn-boundary compaction; else model_limit - margin.
.midloop_trigger <- function(settings = list(), model = "") {
  thr <- settings$midloop_threshold %||%
    getOption("codeagent.midloop_threshold", NA_integer_)
  if (!is.na(thr) && as.numeric(thr) > 0) return(as.integer(thr))
  ml <- settings$model_limit
  if (!is.null(ml)) return(as.integer(ml) - .COMPACT_TRIGGER_MARGIN)
  .auto_compact_threshold(model)
}

# Budget (in tool-result tokens) the micro snip aims to stay under. Default =
# half the auto-compact threshold; override via settings$midloop_snip_target /
# option. NULL/0 means "clear all eligible old tool results" (no budget).
.midloop_snip_target <- function(settings = list(), model = "") {
  t <- settings$midloop_snip_target %||%
    getOption("codeagent.midloop_snip_target", NA_integer_)
  if (!is.na(t) && as.numeric(t) > 0) return(as.integer(t))
  as.integer(.auto_compact_threshold(model) %/% 2L)
}

# Compact mid-loop if enabled AND over threshold. Returns invisibly TRUE when it
# acted. `ctrl` is a CompactionController (or any object with a
# `compact_now(chat, model)` method) used only for the opt-in full path.
.midloop_compact_step <- function(chat, settings = list(), ctrl = NULL,
                                   model = "", compact_model = .HAIKU_MODEL) {
  if (!.midloop_enabled(settings)) return(invisible(FALSE))
  n <- tryCatch(token_count_with_estimation(chat), error = function(e) 0L)
  if (n < .midloop_trigger(settings, model)) return(invisible(FALSE))

  # Opt-in full two-level compact (blocking LLM call, like CC autoCompactIfNeeded).
  if (.midloop_full_enabled(settings) && !is.null(ctrl) &&
      is.function(ctrl$compact_now)) {
    ok <- isTRUE(tryCatch(ctrl$compact_now(chat, compact_model),
                          error = function(e) FALSE))
    if (ok) message(sprintf("[codeagent] mid-loop compact (full, tokens~%d)", n))
    return(invisible(ok))
  }

  # Default: cheap budget-aware micro snip (no LLM call).
  keep   <- as.integer(settings$midloop_keep_recent %||%
                         getOption("codeagent.midloop_keep_recent", 10L))
  target <- .midloop_snip_target(settings, model)
  did <- isTRUE(tryCatch(
    snip_old_tools(chat, keep_recent_turns = keep, target_tokens = target),
    error = function(e) FALSE))
  if (did)
    message(sprintf("[codeagent] mid-loop snip (tokens~%d, keep=%d)", n, keep))
  invisible(did)
}

#' Register mid-loop compaction on a Chat (Plan B)
#'
#' Adds an `on_tool_result` callback that compacts between tool rounds when over
#' threshold. Default = budget-aware micro snip (cheap, no LLM); opt in to a full
#' two-level compact mid-loop with `settings$midloop_full_compact`. The whole
#' feature is gated by `settings$midloop_compact` /
#' `options(codeagent.midloop_compact = TRUE)` (on by default via settings).
#'
#' @param chat An `ellmer::Chat` object.
#' @param settings Named list from [load_settings()].
#' @return Invisibly `chat`.
#' @keywords internal
register_midloop_compaction <- function(chat, settings = list()) {
  force(chat)
  force(settings)
  ctrl          <- tryCatch(CompactionController$new(), error = function(e) NULL)
  model         <- settings$model %||% ""
  compact_model <- settings$compact_model %||% settings$small_fast_model %||%
    .HAIKU_MODEL
  tryCatch(
    chat$on_tool_result(function(result) {
      tryCatch(.midloop_compact_step(chat, settings, ctrl, model, compact_model),
               error = function(e) NULL)
      invisible(NULL)
    }),
    error = function(e) NULL
  )
  invisible(chat)
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

  # How many recent turns to KEEP: token-budget keep-index (mirrors Claude Code
  # calculateMessagesToKeepIndex, sessionMemoryCompact.ts) -- expand backwards
  # from the newest turn until we retain >= min_tokens AND >= min_messages
  # text-bearing turns, capped at max_tokens. Falls back to >= min_messages.
  n_keep   <- .session_keep_count(turns, min_tokens, min_messages, max_tokens)
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
#' @return Invisibly NULL.
#' @keywords internal
full_compact <- function(chat, model = .HAIKU_MODEL, instructions = NULL) {
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
  tryCatch(chat$set_turns(.full_compact_turns(turns, summary_turn)),
           error = function(e) NULL)
  invisible(NULL)
}

# ---------------------------------------------------------------------------
# L4: PTL Fallback (drop oldest turns on 413 / prompt_too_long)
# ---------------------------------------------------------------------------

#' L4: Prompt-too-long fallback -- drop oldest turns
#'
#' Called when the API returns a 413 / prompt_too_long error. When the error
#' message carries a real context limit (Claude Code parses `contextLimit`), drop
#' the oldest turns until the estimate is under ~90% of that limit; otherwise
#' drop a fixed number of oldest turns.
#'
#' @param chat An `ellmer::Chat` object.
#' @param drop_turns Integer. Turns to drop when no limit can be parsed.
#' @param error_msg Character or NULL. The PTL/413 error message to parse.
#' @return Invisibly NULL.
#' @keywords internal
ptl_fallback <- function(chat, drop_turns = 3L, error_msg = NULL) {
  turns <- .safe_get_turns(chat)
  if (length(turns) <= drop_turns) return(invisible(NULL))

  limit <- .parse_ptl_limit(error_msg)
  if (!is.na(limit)) {
    target <- as.integer(limit * 0.9)
    start  <- 1L
    # Drop oldest turns until the remaining estimate fits, but keep >= 1 turn.
    while (start < length(turns) &&
           .estimate_turns_tokens(turns[start:length(turns)]) > target) {
      start <- start + 1L
    }
    new_turns <- turns[start:length(turns)]
  } else {
    new_turns <- turns[(drop_turns + 1L):length(turns)]
  }
  tryCatch(chat$set_turns(new_turns), error = function(e) NULL)
  invisible(NULL)
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

    #' @description Check token usage and compact if needed.
    #' @param chat An `ellmer::Chat` object.
    #' @param model_limit Integer. Model context window token limit.
    #' @param compact_model Character. Model for compaction tasks (haiku).
    #' @return Invisibly NULL.
    maybe_compact = function(chat, model_limit = 200000L,
                              compact_model = .HAIKU_MODEL) {
      # Disabled via env (= CLAUDE_CODE_DISABLE_COMPACT)
      if (!auto_compact_enabled()) return(invisible(NULL))
      # Circuit breaker
      if (private$failures >= .MAX_CONSECUTIVE_COMPACT_FAILS) return(invisible(NULL))

      threshold <- model_limit - .COMPACT_TRIGGER_MARGIN  # e.g. 167K for 200K model
      n         <- token_count_with_estimation(chat)
      if (n < threshold) return(invisible(NULL))

      self$compact_now(chat, compact_model)
      invisible(NULL)
    },

    #' @description Run the two-level compaction now (snip -> session-memory ->
    #'   full 9-section), guarded by the circuit breaker. Unlike
    #'   `maybe_compact()` this skips the token-threshold check, so callers that
    #'   have already decided to compact (e.g. mid-loop) can reuse the exact
    #'   same Claude Code-aligned flow.
    #' @param chat An `ellmer::Chat` object.
    #' @param compact_model Character. Model for compaction tasks (haiku).
    #' @return Invisibly `TRUE` on success, `FALSE` if skipped or failed.
    compact_now = function(chat, compact_model = .HAIKU_MODEL) {
      if (!auto_compact_enabled()) return(invisible(FALSE))
      if (private$failures >= .MAX_CONSECUTIVE_COMPACT_FAILS)
        return(invisible(FALSE))
      ok <- FALSE
      tryCatch({
        # Cheap independent pre-step: clear large old tool results (Claude Code
        # treats snip as a separate step, not part of the summary chain).
        snip_old_tools(chat)
        # Two-level compaction (autoCompact.ts autoCompactIfNeeded): try the
        # incremental session-memory summary first; if it could not run (too
        # few turns), fall back to the full 9-section summary.
        did_sm <- isTRUE(session_memory_compact(chat, model = compact_model))
        if (!did_sm) full_compact(chat, model = compact_model)
        private$failures <- 0L
        ok <- TRUE
      }, error = function(e) {
        private$failures <- private$failures + 1L
        warning("[codeagent] Compaction failed (attempt ", private$failures,
                "): ", conditionMessage(e), call. = FALSE)
      })
      invisible(ok)
    },

    #' @description Handle a prompt-too-long (PTL) error by dropping turns.
    #' @param chat An `ellmer::Chat` object.
    #' @param error An error condition or message string (parsed for a real
    #'   context limit when present).
    handle_ptl_error = function(chat, error = NULL) {
      msg <- if (inherits(error, "condition")) conditionMessage(error)
             else if (is.character(error)) error
             else NULL
      tryCatch(ptl_fallback(chat, error_msg = msg), error = function(e) NULL)
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
