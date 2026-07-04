# Tests for compaction phases 5 (verbatim prompt + summary extraction) and
# 6 (real token counting via get_tokens).

test_that(".COMPACT_SYSTEM_PROMPT is the verbatim 9-section Claude Code prompt", {
  p <- .COMPACT_SYSTEM_PROMPT
  expect_true(grepl("Respond with TEXT ONLY", p, fixed = TRUE))
  expect_true(grepl("1. Primary Request and Intent", p, fixed = TRUE))
  expect_true(grepl("9. Optional Next Step", p, fixed = TRUE))
  expect_true(grepl("All user messages", p, fixed = TRUE))
  expect_true(grepl("<analysis>", p, fixed = TRUE))
  expect_true(grepl("<summary>", p, fixed = TRUE))
  # ASCII-only (R CMD check rejects non-ASCII in source)
  expect_false(any(grepl("[^\x01-\x7f]", p)))
})

test_that(".extract_compact_summary keeps <summary>, drops <analysis>", {
  txt <- "<analysis>\nscratch thoughts\n</analysis>\n<summary>\n1. Primary: do X\n</summary>"
  out <- .extract_compact_summary(txt)
  expect_true(startsWith(out, "Summary:\n"))
  expect_true(grepl("1. Primary: do X", out, fixed = TRUE))
  expect_false(grepl("scratch thoughts", out, fixed = TRUE))
  expect_false(grepl("<analysis>", out, fixed = TRUE))
})

test_that(".extract_compact_summary handles missing tags by dropping analysis", {
  expect_identical(.extract_compact_summary("just a plain summary"),
                   "Summary:\njust a plain summary")
  out <- .extract_compact_summary("<analysis>x</analysis> body text")
  expect_false(grepl("<analysis>", out, fixed = TRUE))
  expect_true(grepl("body text", out, fixed = TRUE))
})

test_that("token_count_with_estimation falls back to estimate when no usage", {
  # A fresh chat has no token usage rows -> falls back to char estimate.
  chat <- ellmer::chat_openai_compatible(base_url = "http://x", model = "m",
                                         credentials = function() "k")
  expect_identical(.last_usage_tokens(chat), NA_integer_)
  # Empty chat estimate is 0.
  expect_identical(token_count_with_estimation(chat), 0L)
})

test_that(".last_usage_tokens sums last input+output when usage present", {
  # Stub a chat-like object exposing get_tokens().
  fake <- list(get_tokens = function() data.frame(
    input        = c(1000, 5000),
    output       = c(200, 800),
    cached_input = c(0, 0),
    cost         = c(0, 0)
  ))
  expect_identical(.last_usage_tokens(fake), 5800L)   # last row 5000 + 800
})

test_that(".parse_ptl_limit extracts the real context limit from 413 messages", {
  expect_identical(
    .parse_ptl_limit("Error 413: prompt is too long: 250000 tokens > 200000 maximum"),
    250000L)   # largest plausible number
  expect_identical(
    .parse_ptl_limit("context_length_exceeded: maximum context length is 128000 tokens"),
    128000L)
  expect_identical(.parse_ptl_limit("some error with no numbers"), NA_integer_)
  expect_identical(.parse_ptl_limit(NULL), NA_integer_)
  expect_identical(.parse_ptl_limit("only 42 small"), NA_integer_)  # < 10000 ignored
})

test_that("maybe_compact respects the disable env and circuit breaker", {
  cc <- CompactionController$new()
  withr::local_envvar(CODEAGENT_DISABLE_COMPACT = "1")
  # Disabled: returns without touching the (NULL) chat -> no error.
  expect_null(cc$maybe_compact(chat = NULL, model_limit = 200000L))
})

test_that("two-level maybe_compact falls back to full when session-memory can't run", {
  # A short conversation: session_memory_compact returns FALSE (too few turns),
  # so the flow would call full_compact. We stub both to record the path without
  # hitting an API.
  calls <- character(0)
  local_mocked_bindings(
    token_count_with_estimation = function(chat) 999999L,   # force over threshold
    snip_old_tools              = function(chat, ...) { calls <<- c(calls, "snip"); invisible(NULL) },
    session_memory_compact      = function(chat, ...) { calls <<- c(calls, "sm"); invisible(FALSE) },
    full_compact                = function(chat, ...) { calls <<- c(calls, "full"); invisible(NULL) }
  )
  cc <- CompactionController$new()
  cc$maybe_compact(chat = list(), model_limit = 200000L)
  expect_identical(calls, c("snip", "sm", "full"))
})

# --- Fidelity fixes: tool-result-aware estimate + full_compact retention ------

test_that("estimate_tokens counts tool-result value, not just text", {
  chat <- ellmer::chat_openai_compatible(base_url = "http://x", model = "m",
                                         credentials = function() "k")
  big <- strrep("y", 700)
  chat$set_turns(list(
    ellmer::Turn("user", list(ellmer::ContentToolResult(value = big)))))
  # previously ~0 (only @text was counted); now reflects the value payload
  expect_gt(estimate_tokens(chat), 100L)
  expect_identical(.content_chars(ellmer::ContentToolResult(value = big)),
                   nchar(big))
  expect_identical(.content_chars(ellmer::ContentText("hello")),
                   nchar("hello"))
})

test_that(".is_plain_user_turn distinguishes plain user turns from tool turns", {
  expect_true(.is_plain_user_turn(
    ellmer::Turn("user", list(ellmer::ContentText("hi")))))
  expect_false(.is_plain_user_turn(
    ellmer::Turn("assistant", list(ellmer::ContentText("hi")))))
  expect_false(.is_plain_user_turn(
    ellmer::Turn("user", list(ellmer::ContentToolResult(value = "x")))))
})

test_that(".full_compact_turns keeps the current-task user turn when safe", {
  summary <- ellmer::Turn("user", list(ellmer::ContentText("[summary]")))
  turns_ok <- list(
    ellmer::Turn("assistant", list(ellmer::ContentText("a"))),
    ellmer::Turn("user", list(ellmer::ContentText("do X")))
  )
  expect_length(.full_compact_turns(turns_ok, summary), 2L)
  # last turn carries a tool result -> summary only (avoid orphaning a pair)
  turns_tool <- list(
    ellmer::Turn("user", list(ellmer::ContentToolResult(value = "res")))
  )
  expect_length(.full_compact_turns(turns_tool, summary), 1L)
})

# --- Manual /compact custom instructions + prompt drift guard ----------------

test_that(".compact_system_prompt biases the prompt with user instructions", {
  expect_identical(.compact_system_prompt(NULL), .COMPACT_SYSTEM_PROMPT)
  expect_identical(.compact_system_prompt(""), .COMPACT_SYSTEM_PROMPT)
  expect_identical(.compact_system_prompt("   "), .COMPACT_SYSTEM_PROMPT)
  p <- .compact_system_prompt("keep the SQL debugging details")
  expect_true(startsWith(p, .COMPACT_SYSTEM_PROMPT))            # base preserved
  expect_match(p, "keep the SQL debugging details", fixed = TRUE)
  expect_match(p, "ADDITIONAL INSTRUCTIONS FROM THE USER")
})

test_that("full_compact accepts an instructions argument", {
  expect_true("instructions" %in% names(formals(full_compact)))
})

test_that(".repl_dispatch captures /compact focus instructions", {
  expect_identical(.repl_dispatch("/compact")$action, "compact")
  d <- .repl_dispatch("/compact keep debug details")
  expect_identical(d$action, "compact")
  expect_identical(d$arg, "keep debug details")
})

test_that("compaction prompt keeps all 9 Claude Code summary sections", {
  sections <- c(
    "1. Primary Request and Intent", "2. Key Technical Concepts",
    "3. Files and Code Sections", "4. Errors and fixes", "5. Problem Solving",
    "6. All user messages", "7. Pending Tasks", "8. Current Work",
    "9. Optional Next Step")
  for (s in sections)
    expect_match(.COMPACT_SYSTEM_PROMPT, s, fixed = TRUE)
})
