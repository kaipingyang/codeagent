test_that(".chat_command_result: /clear signals a clear + feedback", {
  res <- codeagent:::.chat_command_result("clear", "")
  expect_equal(res$action, "clear")
  expect_match(res$feedback, "History cleared")
})

test_that(".chat_command_result: /rewind computes keep from turn count", {
  # 10 turns, rewind 1 exchange (=2 turns) -> keep 8.
  r1 <- codeagent:::.chat_command_result("rewind", "", n_turns = 10L)
  expect_equal(r1$action, "rewind")
  expect_equal(r1$keep, 8L)
  expect_equal(r1$n_back, 1L)
  expect_match(r1$feedback, "1 exchange")

  # rewind 3 -> keep max(0, 10-6)=4.
  r3 <- codeagent:::.chat_command_result("rewind", "3", n_turns = 10L)
  expect_equal(r3$keep, 4L)
  expect_equal(r3$n_back, 3L)

  # never negative; garbage arg -> 1.
  expect_equal(codeagent:::.chat_command_result("rewind", "99", n_turns = 4L)$keep, 0L)
  expect_equal(codeagent:::.chat_command_result("rewind", "abc", n_turns = 4L)$n_back, 1L)
})

test_that(".chat_command_result: /budget formats tokens + percent", {
  res <- codeagent:::.chat_command_result("budget", "",
                                          n_tokens = 50000L, model_limit = 200000L)
  expect_equal(res$action, "append")
  expect_match(res$feedback, "50,000")
  expect_match(res$feedback, "200,000")
  expect_match(res$feedback, "25%")
})

test_that(".chat_command_result: /budget handles zero limit safely", {
  res <- codeagent:::.chat_command_result("budget", "",
                                          n_tokens = 100L, model_limit = 0L)
  expect_match(res$feedback, "0%")
})

test_that(".chat_command_result: /model routes by presence of args", {
  no_arg <- codeagent:::.chat_command_result("model", "")
  expect_equal(no_arg$action, "modal_model")

  with_arg <- codeagent:::.chat_command_result("model", "openai/gpt-4o")
  expect_equal(with_arg$action, "model_switch")
  expect_equal(with_arg$args, "openai/gpt-4o")
})

test_that(".chat_command_result: /compact defers to the handler", {
  res <- codeagent:::.chat_command_result("compact", "focus on tests")
  expect_equal(res$action, "compact")
  expect_equal(res$args, "focus on tests")
})

test_that(".chat_command_result: /sessions formats a list or empty", {
  empty <- codeagent:::.chat_command_result("sessions", "", sessions = list())
  expect_match(empty$feedback, "No saved sessions")

  sess <- list(
    list(session_id = "abcdef123456", title = "First"),
    list(session_id = "0987654321zz", timestamp = "2026-01-01")
  )
  filled <- codeagent:::.chat_command_result("sessions", "", sessions = sess)
  expect_match(filled$feedback, "Recent sessions")
  expect_match(filled$feedback, "abcdef12")   # truncated id
  expect_match(filled$feedback, "First")
})

test_that(".chat_command_result: /help and aliases return help text", {
  for (cmd in c("help", "exit", "quit")) {
    res <- codeagent:::.chat_command_result(cmd, "")
    expect_equal(res$action, "append")
    expect_match(res$feedback, "Slash commands")
    expect_match(res$feedback, "/rewind")
  }
})

test_that(".chat_command_result: unknown command returns guidance", {
  res <- codeagent:::.chat_command_result("frobnicate", "")
  expect_equal(res$action, "append")
  expect_match(res$feedback, "Unknown command: `/frobnicate`")
  expect_match(res$feedback, "/compact")
})

test_that(".format_sessions_feedback tolerates missing fields", {
  expect_equal(codeagent:::.format_sessions_feedback(list()), "No saved sessions.")
  out <- codeagent:::.format_sessions_feedback(list(list(session_id = "xy")))
  expect_match(out, "xy")
})
