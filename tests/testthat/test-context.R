# Tests for dynamic context-window resolution (R/context.R) — Claude Code
# alignment (getContextWindowForModel / getEffectiveContextWindowSize /
# getAutoCompactThreshold).

test_that(".model_context_window resolves known models from the table", {
  expect_identical(.model_context_window("claude-sonnet-4-5"), 200000L)
  expect_identical(.model_context_window("databricks-claude-sonnet-4"), 200000L)
  expect_identical(.model_context_window("gpt-4.1"), 1000000L)
  expect_identical(.model_context_window("gemini-1.5-pro"), 2000000L)
  expect_identical(.model_context_window("deepseek-r1"), 131072L)
})

test_that(".model_context_window falls back to default for unknown models", {
  expect_identical(.model_context_window("totally-unknown-model-xyz"),
                   .MODEL_CONTEXT_WINDOW_DEFAULT)
  expect_identical(.model_context_window(""), .MODEL_CONTEXT_WINDOW_DEFAULT)
})

test_that("[1m] suffix forces a 1M window", {
  expect_identical(.model_context_window("claude-sonnet-4-5[1m]"), 1000000L)
  expect_identical(.model_context_window("some-model[1M]"), 1000000L)
})

test_that("CODEAGENT_MAX_CONTEXT_TOKENS env overrides everything", {
  withr::local_envvar(CODEAGENT_MAX_CONTEXT_TOKENS = "500000")
  expect_identical(.model_context_window("claude-sonnet-4-5"), 500000L)
  expect_identical(.model_context_window("unknown"), 500000L)
})

test_that("sub-100K capability values are not trusted (CC guard) -> default", {
  # gpt-4 maps to 128000 (>=100K) so it is trusted; a small/unknown falls back.
  expect_identical(.model_context_window("gpt-4"), 128000L)
  expect_identical(.model_context_window("some-tiny-8k-model"),
                   .MODEL_CONTEXT_WINDOW_DEFAULT)
})

test_that(".effective_context_window subtracts the output reserve", {
  # claude reserve = min(8192 table, 20000 cap) = 8192
  expect_identical(.effective_context_window("claude-3-5-haiku"),
                   200000L - 8192L)
  # unknown output -> reserve caps at MAX_OUTPUT_TOKENS_FOR_SUMMARY (20000)
  expect_identical(.effective_context_window("totally-unknown"),
                   .MODEL_CONTEXT_WINDOW_DEFAULT - .MAX_OUTPUT_TOKENS_FOR_SUMMARY)
})

test_that("CODEAGENT_AUTO_COMPACT_WINDOW caps the window", {
  withr::local_envvar(CODEAGENT_AUTO_COMPACT_WINDOW = "50000")
  # window capped to 50000, reserve for claude haiku = 8192
  expect_identical(.effective_context_window("claude-3-5-haiku"),
                   50000L - 8192L)
})

test_that(".auto_compact_threshold = effective window minus autocompact buffer", {
  eff <- .effective_context_window("claude-sonnet-4-5")
  expect_identical(.auto_compact_threshold("claude-sonnet-4-5"),
                   eff - .AUTOCOMPACT_BUFFER_TOKENS)
  # Sanity: a 200K claude model triggers at 167K (reserve caps at 20000):
  # 200000 - min(65536, 20000) - 13000 = 167000. Matches the documented point.
  expect_identical(.auto_compact_threshold("claude-sonnet-4-5"),
                   200000L - 20000L - 13000L)
})

test_that("calculate_token_warning_state reports percent_left and thresholds", {
  m  <- "claude-sonnet-4-5"
  th <- .auto_compact_threshold(m)          # 167000
  # Low usage: lots left, no thresholds crossed.
  s1 <- calculate_token_warning_state(1000, m)
  expect_true(s1$percent_left > 90L)
  expect_false(s1$above_warning)
  expect_false(s1$above_compact)
  expect_false(s1$at_blocking)
  # At the compaction threshold: above_compact + above_warning/error true.
  s2 <- calculate_token_warning_state(th, m)
  expect_true(s2$above_compact)
  expect_true(s2$above_warning)
  expect_equal(s2$percent_left, 0L)
  # Near the hard blocking line (effective window - 3000).
  eff <- .effective_context_window(m)
  s3  <- calculate_token_warning_state(eff - 100, m)
  expect_true(s3$at_blocking)
})

test_that("percent_left never goes negative", {
  s <- calculate_token_warning_state(10^9, "claude-sonnet-4-5")
  expect_identical(s$percent_left, 0L)
})
