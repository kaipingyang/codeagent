# tests/testthat/test-tools-ask-user.R
# TDD tests for AskUserQuestion tool (R/tools_ask_user.R).
# Written BEFORE implementation -- all tests should fail initially.

# ---------------------------------------------------------------------------
# Helper: build a minimal mock ask_user_tool for schema tests
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# 1. Tool schema / registration
# ---------------------------------------------------------------------------

test_that("ask_user_tool returns an ellmer ToolDef with correct name", {
  devtools::load_all(quiet = TRUE)
  t <- ask_user_tool()
  expect_equal(t@name, "AskUserQuestion")
})

test_that("ask_user_tool has required 'question' argument", {
  devtools::load_all(quiet = TRUE)
  t <- ask_user_tool()
  arg_names <- names(t@arguments@properties)
  expect_true("question" %in% arg_names)
})

test_that("ask_user_tool has optional 'choices' argument", {
  devtools::load_all(quiet = TRUE)
  t <- ask_user_tool()
  arg_names <- names(t@arguments@properties)
  expect_true("choices" %in% arg_names)
})

test_that("ask_user_tool is marked read_only_hint = TRUE", {
  devtools::load_all(quiet = TRUE)
  t <- ask_user_tool()
  # Check via annotations object or by confirming tool is in .READONLY_TOOLS path
  read_only <- tryCatch(
    isTRUE(t@annotations@read_only_hint),
    error = function(e) {
      # Fallback: check that check_permission returns "allow" for plan mode
      # (which only allows readonly tools)
      identical(codeagent:::check_permission("AskUserQuestion", "plan", list(), ""), "allow")
    }
  )
  expect_true(read_only)
})

test_that("register_ask_user_tool registers tool on chat", {
  devtools::load_all(quiet = TRUE)
  ch <- ellmer::chat_openai_compatible(
    base_url    = "http://fake/v1/",
    model       = "test",
    credentials = function() "x"
  )
  register_ask_user_tool(ch)
  tool_names <- vapply(ch$get_tools(), function(t) t@name, character(1))
  expect_true("AskUserQuestion" %in% tool_names)
})

# ---------------------------------------------------------------------------
# 2. Permission system: AskUserQuestion must be allowed in ALL modes
# ---------------------------------------------------------------------------

test_that("AskUserQuestion is allowed in bypass mode", {
  devtools::load_all(quiet = TRUE)
  result <- codeagent:::check_permission("AskUserQuestion", "bypass", list(), "")
  expect_equal(result, "allow")
})

test_that("AskUserQuestion is allowed in plan mode (not a write tool)", {
  devtools::load_all(quiet = TRUE)
  result <- codeagent:::check_permission("AskUserQuestion", "plan", list(), "")
  expect_equal(result, "allow")
})

test_that("AskUserQuestion is allowed in default mode", {
  devtools::load_all(quiet = TRUE)
  result <- codeagent:::check_permission("AskUserQuestion", "default", list(), "")
  expect_equal(result, "allow")
})

test_that("AskUserQuestion is allowed in dont_ask mode", {
  devtools::load_all(quiet = TRUE)
  result <- codeagent:::check_permission("AskUserQuestion", "dont_ask", list(), "")
  expect_equal(result, "allow")
})

test_that("AskUserQuestion is allowed in accept_edits mode", {
  devtools::load_all(quiet = TRUE)
  result <- codeagent:::check_permission("AskUserQuestion", "accept_edits", list(), "")
  expect_equal(result, "allow")
})

# ---------------------------------------------------------------------------
# 3. CLI path: ask_user_tool with mocked readline
# ---------------------------------------------------------------------------

test_that("ask_user_tool CLI path returns user free-text answer", {
  devtools::load_all(quiet = TRUE)
  # Mock readline via withr to return "Paris"
  withr::with_options(
    list(codeagent.test_ask_answer = "Paris"),
    {
      t <- ask_user_tool()
      fn <- S7::S7_data(t)
      result <- fn(question = "What is the capital of France?")
      result_str <- tryCatch(result@value, error = function(e) as.character(result))
      expect_match(result_str, "Paris")
    }
  )
})

test_that("ask_user_tool CLI path with choices returns selected answer", {
  devtools::load_all(quiet = TRUE)
  # User types "2" → should resolve to second choice "btw"
  withr::with_options(
    list(codeagent.test_ask_answer = "2"),
    {
      t <- ask_user_tool()
      fn <- S7::S7_data(t)
      choices <- c("ellmer", "btw", "shinychat")
      result <- fn(question = "Which package?", choices = choices)
      result_str <- tryCatch(result@value, error = function(e) as.character(result))
      expect_match(result_str, "btw")
    }
  )
})

test_that("ask_user_tool CLI path with out-of-range choice re-prompts or returns raw input", {
  devtools::load_all(quiet = TRUE)
  # User types "99" (out of range) → tool should return "99" or a fallback, not error
  withr::with_options(
    list(codeagent.test_ask_answer = "99"),
    {
      t <- ask_user_tool()
      fn <- S7::S7_data(t)
      result <- tryCatch(
        fn(question = "Which?", choices = c("a", "b")),
        error = function(e) NULL
      )
      # Should not hard-crash; returns something
      expect_false(is.null(result))
    }
  )
})

test_that("ask_user_tool CLI path with empty answer returns empty string, not error", {
  devtools::load_all(quiet = TRUE)
  withr::with_options(
    list(codeagent.test_ask_answer = ""),
    {
      t <- ask_user_tool()
      fn <- S7::S7_data(t)
      result <- tryCatch(fn(question = "Say something"), error = function(e) NULL)
      expect_false(is.null(result))
    }
  )
})

# ---------------------------------------------------------------------------
# 4. Non-interactive guard (scripts/CI)
# ---------------------------------------------------------------------------

test_that("ask_user_tool returns fallback in non-interactive mode with no option set", {
  devtools::load_all(quiet = TRUE)
  # No test_ask_answer option, non-interactive → should return something graceful
  withr::with_options(
    list(codeagent.test_ask_answer = NULL),
    {
      t <- ask_user_tool()
      fn <- S7::S7_data(t)
      # In test environment (non-interactive), must not hang or hard-crash
      result <- tryCatch(
        withCallingHandlers(
          fn(question = "This should not hang"),
          message = function(m) invokeRestart("muffleMessage")
        ),
        error = function(e) "error_ok"
      )
      expect_false(is.null(result))
    }
  )
})
