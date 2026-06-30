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
  expect_identical(d("/sessions")$action, "sessions")
  expect_identical(d("/budget")$action, "budget")
})

test_that(".repl_dispatch parses /model with arg", {
  m <- codeagent:::.repl_dispatch("/model anthropic/claude-haiku-4-5")
  expect_identical(m$action, "model")
  expect_identical(m$arg, "anthropic/claude-haiku-4-5")
})

test_that(".repl_dispatch routes non-meta slash commands to skill", {
  u <- codeagent:::.repl_dispatch("/plan add a feature")
  expect_identical(u$action, "skill")
  expect_identical(u$text, "/plan add a feature")
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

test_that("codeagent_repl /sessions and /budget run without the API", {
  cli <- .mk_client()
  con <- textConnection(c("/sessions", "/budget", "/exit"))
  on.exit(close(con), add = TRUE)
  out <- capture.output(codeagent_repl(cli, stream = FALSE, con = con))
  # Both meta-commands run without errors and the REPL exits cleanly.
  expect_true(any(grepl("Bye", out)))
  expect_false(any(grepl("error", out, ignore.case = TRUE)))
})

# ---------------------------------------------------------------------------
# Tool visibility callbacks
# ---------------------------------------------------------------------------

test_that(".register_repl_tool_callbacks registers without error", {
  ch <- chat_anthropic(model = "claude-sonnet-4-6")
  expect_no_error(codeagent:::.register_repl_tool_callbacks(ch))
})

test_that(".repl_tool_summary falls back to char count when no display title", {
  # Build a minimal ContentToolResult with a value and no display title.
  res <- ellmer::ContentToolResult(value = "hello world")
  s <- codeagent:::.repl_tool_summary(res)
  expect_true(is.character(s) && nzchar(s))
})
