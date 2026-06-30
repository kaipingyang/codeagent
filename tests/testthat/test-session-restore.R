# tests/testthat/test-session-restore.R
# Tests for restore_session_into_chat (harness, shared by CLI --continue/--resume).

library(ellmer)

test_that("restore_session_into_chat resumes a specific session by id", {
  tmp <- withr::local_tempdir()
  ch  <- chat_anthropic(model = "claude-sonnet-4-6")
  ch$set_turns(list(Turn("user", "alpha"), Turn("assistant", "beta")))
  sid <- save_session(ch, cwd = tmp)

  ch2 <- chat_anthropic(model = "claude-sonnet-4-6")
  out <- restore_session_into_chat(ch2, session_id = sid, cwd = tmp)

  expect_identical(out, sid)
  expect_length(ch2$get_turns(), 2L)
  expect_identical(ch2$get_turns()[[1]]@contents[[1]]@text, "alpha")
})

test_that("restore_session_into_chat with NULL id continues the most recent session", {
  tmp <- withr::local_tempdir()
  ch1 <- chat_anthropic(model = "claude-sonnet-4-6")
  ch1$set_turns(list(Turn("user", "older")))
  save_session(ch1, cwd = tmp)
  Sys.sleep(1.1)  # ensure distinct mtime
  ch2 <- chat_anthropic(model = "claude-sonnet-4-6")
  ch2$set_turns(list(Turn("user", "newest"), Turn("assistant", "reply")))
  sid2 <- save_session(ch2, cwd = tmp)

  ch3 <- chat_anthropic(model = "claude-sonnet-4-6")
  out <- restore_session_into_chat(ch3, session_id = NULL, cwd = tmp)

  expect_identical(out, sid2)                     # most recent
  expect_identical(ch3$get_turns()[[1]]@contents[[1]]@text, "newest")
})

test_that("restore_session_into_chat returns NULL when no session exists", {
  tmp <- withr::local_tempdir()
  ch  <- chat_anthropic(model = "claude-sonnet-4-6")
  out <- restore_session_into_chat(ch, session_id = NULL, cwd = tmp)
  expect_null(out)
  expect_length(ch$get_turns(), 0L)
})
