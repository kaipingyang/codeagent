# Tests for task 02 ellmer quick wins: finish_reason (2A) + truncation
# classification (2B).

test_that(".last_finish_reason reads the last turn's finish_reason", {
  # Stub a chat exposing last_turn() with an S3 object carrying @finish_reason.
  mk_chat <- function(fr) {
    turn <- structure(list(), class = "faketurn")
    list(last_turn = function() {
      # emulate S7 @finish_reason via an attribute-backed accessor
      structure(fr, class = "frobj")
    })
  }
  # Use a real ellmer turn to exercise the @finish_reason path.
  chat <- list(last_turn = function() ellmer::Turn("assistant", "hi"))
  # A fresh Turn has NA/empty finish_reason -> NA_character_.
  expect_true(is.na(.last_finish_reason(chat)))
  # No last_turn method -> NA.
  expect_true(is.na(.last_finish_reason(list())))
  expect_true(is.na(.last_finish_reason(NULL)))
})

test_that(".ERR_TRUNCATED matches truncation/filter signals", {
  expect_true(grepl(.ERR_TRUNCATED, "response was truncated", ignore.case = TRUE))
  expect_true(grepl(.ERR_TRUNCATED, "stopped due to max_tokens", ignore.case = TRUE))
  expect_true(grepl(.ERR_TRUNCATED, "content filter triggered", ignore.case = TRUE))
  expect_true(grepl(.ERR_TRUNCATED, "incomplete output", ignore.case = TRUE))
  expect_false(grepl(.ERR_TRUNCATED, "connection timeout", ignore.case = TRUE))
})

test_that(".handle_agent_error retries once on a truncation error", {
  calls <- 0L
  fake_chat <- list(chat = function(input) { calls <<- calls + 1L; "recovered" })
  cc  <- CompactionController$new()
  err <- simpleError("The response was truncated (max_tokens reached)")
  out <- .handle_agent_error(err, fake_chat, "hi", cc)
  expect_identical(out, "recovered")
  expect_identical(calls, 1L)   # exactly one retry
})
