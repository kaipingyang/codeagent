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
    200000L)
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
    .build_outgoing_snapshot = function(...) list(
      turns = list(), pending_turn = NULL,
      structural_tokens = 999999L, provider_tokens = NA_integer_,
      tokens = 999999L
    ),
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

test_that(".session_keep_count keeps recent turns by token budget (CC keep-index)", {
  mk <- function(txt) ellmer::Turn("user", list(ellmer::ContentText(txt)))
  turns <- lapply(1:10, function(i) mk(strrep("x", 100)))
  # tiny min_tokens -> text-msg count governs; keep >= min_text_msgs, capped n-2
  k <- .session_keep_count(turns, min_tokens = 1L, min_text_msgs = 3L,
                           max_tokens = 1e6)
  expect_gte(k, 3L)
  expect_lte(k, 8L)
  # never keeps everything (leaves >= 2 to summarise)
  kall <- .session_keep_count(turns, min_tokens = 1e9, min_text_msgs = 100L,
                              max_tokens = 1e9)
  expect_lte(kall, 8L)
  # max_tokens cap stops expansion early
  kcap <- .session_keep_count(turns, min_tokens = 1e9, min_text_msgs = 100L,
                              max_tokens = 60L)
  expect_lte(kcap, 3L)
})

test_that(".resolve_compact_model prefers small model, else chat model, else haiku", {
  ch <- ellmer::chat_openai_compatible(base_url = "http://x", model = "my-gateway-model",
                                       credentials = function() "k")
  # explicit small/fast model wins
  expect_identical(.resolve_compact_model(ch, list(small_fast_model = "fast-x")), "fast-x")
  # else the chat's own model (guaranteed to exist on the gateway; fixes the
  # Databricks /compact 404 where .HAIKU_MODEL was an invalid Anthropic id)
  expect_identical(.resolve_compact_model(ch, list()), "my-gateway-model")
  # option fallback
  withr::local_options(codeagent.small_fast_model = "opt-fast")
  expect_identical(.resolve_compact_model(ch, list()), "opt-fast")
  # last resort when no chat + nothing configured
  withr::local_options(codeagent.small_fast_model = NULL)
  expect_identical(.resolve_compact_model(NULL, list()), .HAIKU_MODEL)
})


test_that("token count includes cached input and defaults to zero network calls", {
  calls <- 0L
  chat <- list(
    get_tokens = function(...) data.frame(
      input = 10, output = 5, cached_input = 7, cost = 0),
    token_count = function(...) { calls <<- calls + 1L; 99L },
    get_turns = function(...) list())

  expect_equal(token_count_with_estimation(chat), 22L)
  expect_equal(calls, 0L)
  expect_equal(token_count_with_estimation(chat, allow_network = TRUE), 99L)
  expect_equal(calls, 1L)
})

test_that("token count falls back without calling unsupported endpoint", {
  calls <- 0L
  chat <- list(
    get_tokens = function(...) data.frame(),
    token_count = function(...) { calls <<- calls + 1L; stop("unsupported") },
    get_turns = function(...) list(ellmer::Turn("user", "1234567")))

  expect_equal(token_count_with_estimation(chat), 2L)
  expect_equal(calls, 0L)
  expect_equal(token_count_with_estimation(chat, allow_network = TRUE), 2L)
  expect_equal(calls, 1L)
})

# --- Adaptive compaction: structured summary serialization ------------------

test_that("compact serializer preserves structured tool request and result", {
  req <- ellmer::ContentToolRequest(
    id = "tool-serializer-1",
    name = "Read",
    arguments = list(path = "synthetic.txt", line = 7L)
  )
  res <- ellmer::ContentToolResult(
    request = req,
    value = "SYNTHETIC_RESULT_VALUE",
    error = "synthetic failure",
    extra = list(
      display = "UI_ONLY_DISPLAY_SENTINEL",
      codeagent = list(artifact = "UI_ONLY_ARTIFACT_SENTINEL")
    )
  )
  turns <- list(
    ellmer::Turn("assistant", list(
      ellmer::ContentText("checking the file"),
      req
    )),
    ellmer::Turn("user", list(res))
  )

  out <- .serialize_compact_turns(turns)

  expect_match(out, "ROLE: assistant", fixed = TRUE)
  expect_match(out, "TOOL_REQUEST", fixed = TRUE)
  expect_match(out, "tool-serializer-1", fixed = TRUE)
  expect_match(out, "Read", fixed = TRUE)
  expect_match(out, "synthetic.txt", fixed = TRUE)
  expect_match(out, "TOOL_RESULT", fixed = TRUE)
  expect_match(out, "SYNTHETIC_RESULT_VALUE", fixed = TRUE)
  expect_match(out, "synthetic failure", fixed = TRUE)
  expect_false(grepl("UI_ONLY_DISPLAY_SENTINEL", out, fixed = TRUE))
  expect_false(grepl("UI_ONLY_ARTIFACT_SENTINEL", out, fixed = TRUE))
})

test_that("compact serializer uses typed placeholders for non-text media", {
  turns <- list(ellmer::Turn("user", list(
    ellmer::ContentText("inspect this image"),
    ellmer::ContentImageRemote("https://example.test/image.png")
  )))

  out <- .serialize_compact_turns(turns)

  expect_match(out, "inspect this image", fixed = TRUE)
  expect_match(out, "MEDIA", fixed = TRUE)
  expect_match(out, "ContentImageRemote", fixed = TRUE)
  expect_false(grepl("https://example.test/image.png", out, fixed = TRUE))
})

test_that("compact serializer bounds input while retaining recent active task", {
  turns <- list(
    ellmer::Turn("user", list(ellmer::ContentText(
      paste0("EARLY_CONTEXT_START ", strrep("a", 900))))),
    ellmer::Turn("assistant", list(ellmer::ContentText(
      paste0("MIDDLE_CONTEXT ", strrep("b", 900))))),
    ellmer::Turn("user", list(ellmer::ContentText(
      paste0("LATEST_ACTIVE_TASK ", strrep("c", 900)))))
  )

  out <- .serialize_compact_turns(turns, max_chars = 700L)

  expect_lte(nchar(out), 700L)
  expect_match(out, "EARLY_CONTEXT_START", fixed = TRUE)
  expect_match(out, "LATEST_ACTIVE_TASK", fixed = TRUE)
  expect_match(out, "serialization truncated", fixed = TRUE)
})

test_that("full compaction sends structured tool content to summarizer", {
  req <- ellmer::ContentToolRequest(
    id = "tool-full-1",
    name = "SyntheticTool",
    arguments = list(query = "STRUCTURED_ARGUMENT_SENTINEL")
  )
  chat <- ellmer::chat_openai_compatible(
    base_url = "http://x", model = "m", credentials = function() "k")
  chat$set_turns(list(
    ellmer::Turn("user", list(ellmer::ContentText("first"))),
    ellmer::Turn("assistant", list(req)),
    ellmer::Turn("user", list(ellmer::ContentToolResult(
      request = req,
      value = "STRUCTURED_RESULT_SENTINEL",
      extra = list(display = "DISPLAY_MUST_NOT_REACH_SUMMARY")
    ))),
    ellmer::Turn("assistant", list(ellmer::ContentText("done")))
  ))
  captured <- new.env(parent = emptyenv())
  captured$input <- NULL
  fake_compactor <- list(chat = function(input) {
    captured$input <- input
    "<summary>safe summary</summary>"
  })
  local_mocked_bindings(
    .make_compact_chat = function(...) fake_compactor
  )

  expect_true(full_compact(chat, model = "compact-model"))

  expect_match(captured$input, "STRUCTURED_ARGUMENT_SENTINEL", fixed = TRUE)
  expect_match(captured$input, "STRUCTURED_RESULT_SENTINEL", fixed = TRUE)
  expect_false(grepl("DISPLAY_MUST_NOT_REACH_SUMMARY", captured$input,
                     fixed = TRUE))
})

test_that("incremental compaction sends structured tool content to summarizer", {
  req <- ellmer::ContentToolRequest(
    id = "tool-incremental-1",
    name = "SyntheticTool",
    arguments = list(query = "INCREMENTAL_ARGUMENT_SENTINEL")
  )
  chat <- ellmer::chat_openai_compatible(
    base_url = "http://x", model = "m", credentials = function() "k")
  chat$set_turns(list(
    ellmer::Turn("user", list(ellmer::ContentText(strrep("a", 40)))),
    ellmer::Turn("assistant", list(req)),
    ellmer::Turn("user", list(ellmer::ContentToolResult(
      request = req, value = "INCREMENTAL_RESULT_SENTINEL"))),
    ellmer::Turn("assistant", list(ellmer::ContentText("recent one"))),
    ellmer::Turn("user", list(ellmer::ContentText("recent two"))),
    ellmer::Turn("assistant", list(ellmer::ContentText("recent three")))
  ))
  captured <- new.env(parent = emptyenv())
  captured$input <- NULL
  fake_compactor <- list(chat = function(input) {
    captured$input <- input
    "incremental summary"
  })
  local_mocked_bindings(
    .make_compact_chat = function(...) fake_compactor
  )

  expect_true(session_memory_compact(
    chat,
    model = "compact-model",
    min_messages = 1L,
    min_tokens = 1L,
    max_tokens = 10000L
  ))
  expect_match(captured$input, "INCREMENTAL_ARGUMENT_SENTINEL", fixed = TRUE)
  expect_match(captured$input, "INCREMENTAL_RESULT_SENTINEL", fixed = TRUE)
})

test_that("controller uses the unified model-aware threshold", {
  calls <- 0L
  after_summary <- FALSE
  local_mocked_bindings(
    .build_outgoing_snapshot = function(...) {
      tokens <- if (after_summary) 10L else 175000L
      list(
        turns = list(), pending_turn = NULL,
        structural_tokens = tokens, provider_tokens = NA_integer_,
        tokens = tokens
      )
    },
    snip_old_tools = function(...) {
      calls <<- calls + 1L
      invisible(FALSE)
    },
    session_memory_compact = function(...) {
      after_summary <<- TRUE
      invisible(TRUE)
    },
    full_compact = function(...) stop("full summary should not run")
  )
  ctrl <- CompactionController$new()

  ctrl$maybe_compact(
    chat = list(),
    model_limit = 200000L,
    compact_model = "compact-model",
    model = "claude-3-5-haiku"
  )
  expect_identical(calls, 0L)

  ctrl$maybe_compact(
    chat = list(),
    model_limit = 200000L,
    compact_model = "compact-model",
    model = "totally-unknown"
  )
  expect_identical(calls, 1L)
})

# --- Adaptive compaction: pair-safe PTL recovery ----------------------------

test_that("PTL usage parser separates actual tokens from the context limit", {
  usage <- .parse_ptl_usage(
    "Error 413: prompt is too long: 250000 tokens > 200000 maximum"
  )
  expect_identical(usage$actual, 250000L)
  expect_identical(usage$limit, 200000L)
  expect_identical(.parse_ptl_limit(
    "Error 413: prompt is too long: 250000 tokens > 200000 maximum"
  ), 200000L)
})

test_that("PTL fallback drops complete rounds and preserves tool pairs", {
  req1 <- ellmer::ContentToolRequest(
    id = "ptl-tool-old", name = "OldTool", arguments = list(x = 1L))
  req2 <- ellmer::ContentToolRequest(
    id = "ptl-tool-new", name = "NewTool", arguments = list(x = 2L))
  chat <- ellmer::chat_openai_compatible(
    base_url = "http://x", model = "m", credentials = function() "k")
  chat$set_turns(list(
    ellmer::Turn("user", list(ellmer::ContentText(
      paste0("old request ", strrep("a", 50000))))),
    ellmer::Turn("assistant", list(req1)),
    ellmer::Turn("user", list(ellmer::ContentToolResult(
      request = req1, value = "old result"))),
    ellmer::Turn("assistant", list(ellmer::ContentText("old done"))),
    ellmer::Turn("user", list(ellmer::ContentText("new request"))),
    ellmer::Turn("assistant", list(req2)),
    ellmer::Turn("user", list(ellmer::ContentToolResult(
      request = req2, value = "new result"))),
    ellmer::Turn("assistant", list(ellmer::ContentText("new done")))
  ))
  pending <- ellmer::Turn(
    "user", list(ellmer::ContentText("PTL_PENDING_SENTINEL")))

  decision <- ptl_fallback(
    chat,
    error_msg = "prompt too long: 30000 tokens > 20000 maximum",
    pending_turn = pending
  )
  remaining <- chat$get_turns()
  serialized <- .serialize_compact_turns(remaining)
  outgoing <- .build_outgoing_snapshot(
    chat, pending_turn = pending, use_provider_usage = FALSE)
  outgoing_text <- .serialize_compact_turns(outgoing$turns)

  expect_identical(decision$action, "ptl_group_drop")
  expect_gte(decision$dropped_groups, 1L)
  expect_true(decision$structure_valid)
  expect_true(.validate_compaction_structure(remaining)$valid)
  expect_false(grepl("ptl-tool-old", serialized, fixed = TRUE))
  expect_match(serialized, "ptl-tool-new", fixed = TRUE)
  expect_identical(
    lengths(regmatches(outgoing_text, gregexpr(
      "PTL_PENDING_SENTINEL", outgoing_text, fixed = TRUE))),
    1L
  )
  expect_false(any(vapply(
    remaining,
    function(turn) grepl("PTL_PENDING_SENTINEL",
                         .serialize_compact_turns(list(turn)), fixed = TRUE),
    logical(1L)
  )))
})

test_that("PTL fallback uses a twenty-percent target when limit is unavailable", {
  chat <- ellmer::chat_openai_compatible(
    base_url = "http://x", model = "m", credentials = function() "k")
  chat$set_turns(list(
    ellmer::Turn("user", list(ellmer::ContentText(strrep("a", 5000)))),
    ellmer::Turn("assistant", list(ellmer::ContentText("old answer"))),
    ellmer::Turn("user", list(ellmer::ContentText("latest request"))),
    ellmer::Turn("assistant", list(ellmer::ContentText("latest answer")))
  ))

  decision <- ptl_fallback(chat, error_msg = "prompt too long")

  expect_identical(decision$reason, "fallback_twenty_percent")
  expect_gte(decision$dropped_groups, 1L)
  expect_true(decision$after_estimate < decision$before_estimate)
})

test_that("resource manager replaces multiple large results in one budget pass", {
  req1 <- ellmer::ContentToolRequest(
    id = "resource-tool-1", name = "Tool", arguments = list())
  req2 <- ellmer::ContentToolRequest(
    id = "resource-tool-2", name = "Tool", arguments = list())
  chat <- ellmer::chat_openai_compatible(
    base_url = "http://x", model = "m", credentials = function() "k")
  chat$set_turns(list(
    ellmer::Turn("assistant", list(req1)),
    ellmer::Turn("user", list(ellmer::ContentToolResult(
      request = req1, value = strrep("a", 1200)))),
    ellmer::Turn("assistant", list(req2)),
    ellmer::Turn("user", list(ellmer::ContentToolResult(
      request = req2, value = strrep("b", 1200))))
  ))
  state <- ContentReplacementState$new(soft_ceiling = 1L)

  state$maybe_replace(chat)

  values <- unlist(lapply(chat$get_turns(), function(turn) {
    contents <- tryCatch(turn@contents, error = function(e) list())
    vapply(contents, function(content) {
      if (!identical(.compact_content_type(content), "ContentToolResult"))
        return(NA_character_)
      tryCatch(as.character(content@value), error = function(e) NA_character_)
    }, character(1L))
  }), use.names = FALSE)
  values <- values[!is.na(values)]
  expect_true(all(values == "[Tool result replaced to save context space]"))
  expect_setequal(state$replaced_ids(), c("resource-tool-1", "resource-tool-2"))
})

test_that("PTL fallback refuses to mutate orphaned tool results", {
  req <- ellmer::ContentToolRequest(
    id = "orphan-tool", name = "Tool", arguments = list())
  chat <- ellmer::chat_openai_compatible(
    base_url = "http://x", model = "m", credentials = function() "k")
  turns <- list(
    ellmer::Turn("user", list(ellmer::ContentToolResult(
      request = req, value = "orphan result"))),
    ellmer::Turn("assistant", list(ellmer::ContentText("later"))),
    ellmer::Turn("user", list(ellmer::ContentText("latest")))
  )
  chat$set_turns(turns)
  before <- .serialize_compact_turns(chat$get_turns())

  decision <- ptl_fallback(chat, error_msg = "prompt too long")

  expect_identical(decision$reason, "invalid_structure")
  expect_false(decision$success)
  expect_false(decision$changed)
  expect_identical(.serialize_compact_turns(chat$get_turns()), before)
})

test_that("incremental summary moves a split to a complete API round", {
  req <- ellmer::ContentToolRequest(
    id = "split-tool", name = "Tool", arguments = list())
  turns <- list(
    ellmer::Turn("user", list(ellmer::ContentText("first request"))),
    ellmer::Turn("assistant", list(req)),
    ellmer::Turn("user", list(ellmer::ContentToolResult(
      request = req, value = "tool result"))),
    ellmer::Turn("assistant", list(ellmer::ContentText("first done"))),
    ellmer::Turn("user", list(ellmer::ContentText("latest request"))),
    ellmer::Turn("assistant", list(ellmer::ContentText("latest answer")))
  )

  expect_identical(.safe_session_summary_index(turns, 2L), 4L)

  chat <- ellmer::chat_openai_compatible(
    base_url = "http://x", model = "m", credentials = function() "k")
  chat$set_turns(turns)
  fake_compactor <- list(chat = function(input) "pair-safe summary")
  local_mocked_bindings(
    .session_keep_count = function(...) 4L,
    .make_compact_chat = function(...) fake_compactor
  )

  expect_true(session_memory_compact(
    chat,
    model = "compact-model",
    min_messages = 1L,
    min_tokens = 1L,
    max_tokens = 10000L
  ))
  expect_true(.validate_compaction_structure(chat$get_turns())$valid)
})
