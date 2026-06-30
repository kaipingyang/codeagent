# tests/testthat/test-repl.R
# Tests for the CLI REPL (M4): pure dispatch + loop via textConnection.

library(ellmer)

# ---------------------------------------------------------------------------
# .repl_dispatch (pure)
# ---------------------------------------------------------------------------

test_that(".repl_dispatch classifies lines correctly", {
  d <- codeagent:::.repl_dispatch
  expect_identical(d("")$action, "noop")
  expect_identical(d("   ")$action, "noop")
  expect_identical(d("hello")$action, "prompt")
  expect_identical(d("hello")$text, "hello")
  expect_identical(d("/exit")$action, "exit")
  expect_identical(d("/quit")$action, "exit")
  expect_identical(d("/help")$action, "help")
  expect_identical(d("/clear")$action, "clear")
  expect_identical(d("/compact")$action, "compact")
})

test_that(".repl_dispatch parses /model with arg", {
  m <- codeagent:::.repl_dispatch("/model anthropic/claude-haiku-4-5")
  expect_identical(m$action, "model")
  expect_identical(m$arg, "anthropic/claude-haiku-4-5")
})

test_that(".repl_dispatch flags unknown slash commands", {
  u <- codeagent:::.repl_dispatch("/frobnicate")
  expect_identical(u$action, "unknown")
  expect_identical(u$cmd, "frobnicate")
})

# ---------------------------------------------------------------------------
# codeagent_repl loop (textConnection, no API)
# ---------------------------------------------------------------------------

.mk_client <- function() {
  ch <- chat_anthropic(model = "claude-sonnet-4-6")
  ch$set_turns(list(Turn("user", "old"), Turn("assistant", "reply")))
  codeagent_client(ch, permission_mode = "bypass", btw_groups = NULL, cwd = getwd())
}

test_that("codeagent_repl rejects non-clients", {
  expect_error(codeagent_repl("nope"), "CodagentClient")
})

test_that("codeagent_repl runs /help, /clear, /exit without hitting the API", {
  cli <- .mk_client()
  con <- textConnection(c("/help", "/clear", "/exit"))
  on.exit(close(con), add = TRUE)
  out <- capture.output(codeagent_repl(cli, stream = FALSE, con = con))
  expect_true(any(grepl("Commands:", out)))
  expect_true(any(grepl("history cleared", out)))
  expect_true(any(grepl("Bye", out)))
  expect_length(cli$chat$get_turns(), 0L)   # /clear emptied history
})

test_that("codeagent_repl /model switches the model in place", {
  cli <- .mk_client()
  con <- textConnection(c("/model anthropic/claude-haiku-4-5", "/exit"))
  on.exit(close(con), add = TRUE)
  out <- capture.output(codeagent_repl(cli, stream = FALSE, con = con))
  expect_true(any(grepl("model:", out)))
  expect_identical(cli$chat$get_model(), "claude-haiku-4-5")  # Route A: same obj
})

test_that("codeagent_repl exits cleanly on EOF (empty connection)", {
  cli <- .mk_client()
  con <- textConnection(character(0))
  on.exit(close(con), add = TRUE)
  expect_silent(invisible(capture.output(codeagent_repl(cli, stream = FALSE, con = con))))
})
