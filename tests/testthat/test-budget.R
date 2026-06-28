test_that("BudgetTracker stops at budget ratio threshold", {
  bt <- BudgetTracker$new()
  # Below threshold: no stop
  expect_false(bt$should_stop(100000L, 200000L, iteration = 5L))
  # At 90% threshold: stop
  expect_true(bt$should_stop(180001L, 200000L, iteration = 5L))
  # Exactly at threshold (>= comparison)
  expect_true(bt$should_stop(as.integer(200000L * .BUDGET_STOP_RATIO), 200000L,
                              iteration = 5L))
})

test_that("BudgetTracker skips budget check for sub-agents", {
  bt <- BudgetTracker$new()
  # Even at 100% usage, sub-agents are exempt
  expect_false(bt$should_stop(200000L, 200000L, iteration = 1L,
                               is_subagent = TRUE))
})

test_that("BudgetTracker does not stop before minimum iterations", {
  bt <- BudgetTracker$new()
  # Even high token count, stop is deferred until iteration >= min
  min_iter <- .BUDGET_MIN_ITERATIONS
  for (i in seq_len(min_iter - 1L)) {
    expect_false(bt$should_stop(190000L, 200000L, iteration = i))
  }
})

test_that("BudgetTracker detects diminishing returns", {
  bt     <- BudgetTracker$new()
  max_t  <- 200000L
  growth <- .BUDGET_MIN_GROWTH - 1L  # just below threshold (e.g. 499)

  # First call: big initial jump to establish prev_tokens baseline
  # (delta is large, so same_count stays 0)
  expect_false(bt$should_stop(50000L, max_t, iteration = 5L))

  # Now simulate .BUDGET_MAX_STALL_TURNS consecutive low-growth turns
  base <- 50000L
  for (i in seq_len(.BUDGET_MAX_STALL_TURNS)) {
    tokens <- base + i * growth
    result <- bt$should_stop(tokens, max_t, iteration = 5L + i)
    if (i < .BUDGET_MAX_STALL_TURNS) {
      expect_false(result, info = paste("Should not stop at stall turn", i))
    } else {
      expect_true(result, info = "Should stop after max stall turns")
    }
  }
})

test_that("BudgetTracker resets same_count on significant growth", {
  bt <- BudgetTracker$new()
  max_t <- 200000L
  # Force same_count to 2
  bt$should_stop(1000L, max_t, iteration = 5L)
  bt$should_stop(1100L, max_t, iteration = 6L)
  # Large jump resets the counter
  bt$should_stop(100000L, max_t, iteration = 7L)
  # Now small growth again — counter starts from 0, should not stop yet
  expect_false(bt$should_stop(100100L, max_t, iteration = 8L))
})

test_that("BudgetTracker reset() clears all state", {
  bt <- BudgetTracker$new()
  bt$should_stop(180000L, 200000L, iteration = 5L)
  bt$reset()
  state <- bt$state()
  expect_equal(state$prev_tokens, 0L)
  expect_equal(state$same_count,  0L)
})

test_that("BudgetTracker: model_limit (not max_turns*2000) is the right max_tokens arg", {
  # Regression guard for the query.R bug where max_turns*2000 was passed instead
  # of model_limit. With max_turns=1, the old code would use 2000 as the limit,
  # causing spurious stops at 1800 tokens. The fix uses settings$model_limit.
  bt <- BudgetTracker$new()
  model_limit <- 200000L

  # 1800 tokens is 90% of 2000 (old buggy threshold with max_turns=1),
  # but only 0.9% of 200K -- should NOT trigger a stop.
  expect_false(bt$should_stop(1800L, model_limit, iteration = 5L),
               info = "1800 tokens << 90% of 200K model_limit")

  # 180001 is just over 90% of 200K -- should stop.
  bt2 <- BudgetTracker$new()
  expect_true(bt2$should_stop(180001L, model_limit, iteration = 5L))
})
