# tests/testthat/test-turn-pipeline.R
# Unit tests for R/turn_pipeline.R: .inject_reminder_to_input, .turn_setup,
# .turn_teardown.

test_that(".inject_reminder_to_input handles character input", {
  result <- codeagent:::.inject_reminder_to_input("hello", "reminder")
  expect_equal(result, "hello\n\nreminder")
})

test_that(".inject_reminder_to_input handles list input (text + attachment)", {
  input  <- list("hello", list(type = "image"))
  result <- codeagent:::.inject_reminder_to_input(input, "reminder")
  expect_equal(result[[1L]], "hello\n\nreminder")
  expect_equal(length(result), 2L)
  expect_equal(result[[2L]], list(type = "image"))
})

test_that(".inject_reminder_to_input returns input unchanged for empty reminder", {
  expect_equal(codeagent:::.inject_reminder_to_input("hello", ""),  "hello")
  expect_equal(codeagent:::.inject_reminder_to_input("hello", NULL), "hello")
})

test_that(".turn_setup returns character input with reminder injected", {
  skip_if_not_installed("ellmer")
  ch <- ellmer::chat_anthropic(model = "claude-haiku-4-5-20251001",
                               credentials = function() "fake")
  result <- codeagent:::.turn_setup(ch, "test prompt", iteration = 1L,
                                    cwd = getwd())
  # reminder is injected (system-reminder block appended)
  expect_true(grepl("test prompt", result))
  expect_true(grepl("<system-reminder>", result))
})

test_that(".turn_setup with iteration > 1 still returns the input", {
  skip_if_not_installed("ellmer")
  ch <- ellmer::chat_anthropic(model = "claude-haiku-4-5-20251001",
                               credentials = function() "fake")
  # iteration > 1: no memory recall (expensive), but date/cwd still injected
  result <- codeagent:::.turn_setup(ch, "test", iteration = 2L,
                                    cwd = getwd())
  expect_true(grepl("test", result))
  expect_true(grepl("Agent loop iteration: 2", result))
})

test_that(".turn_setup with list input preserves attachment", {
  skip_if_not_installed("ellmer")
  ch <- ellmer::chat_anthropic(model = "claude-haiku-4-5-20251001",
                               credentials = function() "fake")
  input  <- list("tell me about this image", list(type = "image_url"))
  result <- codeagent:::.turn_setup(ch, input, iteration = 2L, cwd = getwd())
  # list shape preserved, reminder injected into text element
  expect_true(is.list(result))
  expect_true(grepl("tell me about this image", result[[1L]]))
  expect_equal(length(result), 2L)
})

test_that(".turn_teardown returns required fields", {
  skip_if_not_installed("ellmer")
  tmp <- withr::local_tempdir()
  ch  <- ellmer::chat_anthropic(model = "claude-haiku-4-5-20251001",
                                credentials = function() "fake")
  usage <- codeagent:::.turn_teardown(ch, cwd = tmp, session_id = NULL)
  expect_true(is.list(usage))
  expect_true("n_tokens"     %in% names(usage))
  expect_true("model_limit"  %in% names(usage))
  expect_true("warning_state" %in% names(usage))
  expect_true("cost_last"    %in% names(usage))
  expect_true(is.integer(usage$n_tokens) || is.numeric(usage$n_tokens))
})

test_that(".turn_teardown saves session file when session_id provided", {
  skip_if_not_installed("ellmer")
  tmp <- withr::local_tempdir()
  ch  <- ellmer::chat_anthropic(model = "claude-haiku-4-5-20251001",
                                credentials = function() "fake")
  sid <- "test-turn-teardown-session"
  codeagent:::.turn_teardown(ch, cwd = tmp, session_id = sid)
  session_dir <- codeagent:::.get_project_session_dir(tmp)
  expect_true(file.exists(file.path(session_dir, paste0(sid, ".jsonl"))))
})
