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
# codeagent_console loop (textConnection, no API)
# ---------------------------------------------------------------------------

.mk_client <- function() {
  ch <- chat_anthropic(model = "claude-sonnet-4-6")
  ch$set_turns(list(Turn("user", "old"), Turn("assistant", "reply")))
  codeagent_client(ch, permission_mode = "bypass", btw_groups = NULL, cwd = getwd())
}

test_that("codeagent_console rejects non-clients", {
  expect_error(codeagent_console("nope"), "CodeagentClient")
})

test_that("codeagent_console runs /help, /clear, /exit without hitting the API", {
  cli <- .mk_client()
  con <- textConnection(c("/help", "/clear", "/exit"))
  on.exit(close(con), add = TRUE)
  out <- capture.output(codeagent_console(cli, stream = FALSE, con = con, quiet = TRUE))
  expect_true(any(grepl("Commands:", out)))
  expect_true(any(grepl("history cleared", out)))
  expect_true(any(grepl("Bye", out)))
  expect_length(cli$chat$get_turns(), 0L)   # /clear emptied history
})

test_that("codeagent_console /model switches the model in place", {
  cli <- .mk_client()
  con <- textConnection(c("/model anthropic/claude-haiku-4-5", "/exit"))
  on.exit(close(con), add = TRUE)
  out <- capture.output(codeagent_console(cli, stream = FALSE, con = con, quiet = TRUE))
  expect_true(any(grepl("model:", out)))
  expect_identical(cli$chat$get_model(), "claude-haiku-4-5")  # Route A: same obj
})

test_that("codeagent_console exits cleanly on EOF (empty connection)", {
  cli <- .mk_client()
  con <- textConnection(character(0))
  on.exit(close(con), add = TRUE)
  expect_silent(invisible(capture.output(codeagent_console(cli, stream = FALSE, con = con, quiet = TRUE))))
})

test_that("codeagent_console /sessions and /budget run without the API", {
  cli <- .mk_client()
  con <- textConnection(c("/sessions", "/budget", "/exit"))
  on.exit(close(con), add = TRUE)
  out <- capture.output(codeagent_console(cli, stream = FALSE, con = con, quiet = TRUE))
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

test_that("console tool-card helpers render label/summary (color-agnostic)", {
  req <- .repl_tool_request_line("Read", "R/utils.R")
  expect_true(grepl("Read", req) && grepl("R/utils.R", req))
  expect_true(grepl("\n", req))
  res <- .repl_tool_result_line("42 lines")
  expect_true(grepl("42 lines", res))
  # empty hint -> no trailing hint text, still renders the label
  expect_true(grepl("Bash", .repl_tool_request_line("Bash", "")))
})

test_that(".render_markdown highlights code + degrades to plain off-tty", {
  md <- "T\n\n```r\nadd <- function(a,b) a+b\n```\n\nUse `add(1,2)` and **x**."
  withr::local_options(cli.num_colors = 256)
  r <- .render_markdown(md)
  expect_true(grepl("add", r) && grepl("\033\\[", r))   # code kept + ANSI
  withr::local_options(cli.num_colors = 1)
  r2 <- .render_markdown(md)
  expect_true(grepl("add", r2)); expect_false(grepl("\033\\[", r2))  # plain, no ANSI
  # empty input safe
  expect_identical(.render_markdown(""), "")
})

# ---------------------------------------------------------------------------
# Ctrl+C / interrupt + callback deduplication (Step 2)
# ---------------------------------------------------------------------------

test_that(".register_repl_tool_callbacks does not stack via .chat_once", {
  skip_if_not_installed("ellmer")
  ch <- ellmer::chat_anthropic(model = "claude-haiku-4-5-20251001",
                               credentials = function() "fake")

  # First call: registers and returns TRUE
  r1 <- codeagent:::.chat_once(ch, "repl_display")
  if (isTRUE(r1)) codeagent:::.register_repl_tool_callbacks(ch)

  # Second call: .chat_once returns FALSE -> no second registration
  r2 <- codeagent:::.chat_once(ch, "repl_display")
  expect_false(r2)   # guard prevents stacking
})
