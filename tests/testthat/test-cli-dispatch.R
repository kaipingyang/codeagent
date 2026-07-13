# tests/testthat/test-cli-dispatch.R
# Unit tests for R/cli_dispatch.R

test_that(".ca_resolve_mode returns default when yolo is FALSE", {
  expect_equal(codeagent:::.ca_resolve_mode(FALSE), "default")
  expect_equal(codeagent:::.ca_resolve_mode(),       "default")
})

test_that(".ca_resolve_mode returns bypass when yolo is TRUE", {
  expect_equal(codeagent:::.ca_resolve_mode(TRUE), "bypass")
})

test_that(".ca_dispatch empty argv -> chat", {
  r <- codeagent:::.ca_dispatch()
  expect_equal(r$cmd, "chat")
  expect_equal(r$rest, character())
})

test_that(".ca_dispatch with prompt -> run", {
  r <- codeagent:::.ca_dispatch(c("hello world"))
  expect_equal(r$cmd, "run")
  expect_equal(r$rest, "hello world")
})

test_that(".ca_dispatch run subcommand explicit", {
  r <- codeagent:::.ca_dispatch(c("run", "hello"))
  expect_equal(r$cmd, "run")
  expect_equal(r$rest, "hello")
})

test_that(".ca_dispatch app subcommand", {
  r <- codeagent:::.ca_dispatch(c("app"))
  expect_equal(r$cmd, "app")
  expect_equal(r$rest, character())
})

test_that(".ca_dispatch skills subcommand with rest", {
  r <- codeagent:::.ca_dispatch(c("skills", "list"))
  expect_equal(r$cmd, "skills")
  expect_equal(r$rest, "list")
})

test_that(".ca_dispatch chat explicit", {
  r <- codeagent:::.ca_dispatch(c("chat"))
  expect_equal(r$cmd, "chat")
  expect_equal(r$rest, character())
})

test_that(".ca_dispatch print_mode TRUE empty argv -> run", {
  r <- codeagent:::.ca_dispatch(character(), print_mode = TRUE)
  expect_equal(r$cmd, "run")
  expect_equal(r$rest, character())
})

test_that(".ca_dispatch print_mode TRUE with argv -> run with rest", {
  r <- codeagent:::.ca_dispatch(c("my", "query"), print_mode = TRUE)
  expect_equal(r$cmd, "run")
  expect_equal(r$rest, c("my", "query"))
})

test_that(".ca_dispatch mcp subcommand", {
  r <- codeagent:::.ca_dispatch(c("mcp"))
  expect_equal(r$cmd, "mcp")
})

test_that(".ca_dispatch info subcommand", {
  r <- codeagent:::.ca_dispatch(c("info", "--json"))
  expect_equal(r$cmd, "info")
  expect_equal(r$rest, "--json")
})

test_that(".ca_dispatch NULL argv treated as empty", {
  r <- codeagent:::.ca_dispatch(NULL)
  expect_equal(r$cmd, "chat")
})

# ---------------------------------------------------------------------------
# ca_output JSON format (new in plan #21)
# ---------------------------------------------------------------------------

test_that("ca_output text format prints response", {
  out <- capture.output(
    codeagent:::.ca_format_output("hello world", output_fmt = "text")
  )
  expect_true(any(grepl("hello world", out)))
})

test_that("ca_output json format emits valid JSON with response field", {
  skip_if_not_installed("jsonlite")
  out <- capture.output(
    codeagent:::.ca_format_output("hello", output_fmt = "json", session_id = "abc-123")
  )
  parsed <- jsonlite::fromJSON(paste(out, collapse = ""))
  expect_equal(parsed$response, "hello")
  expect_equal(parsed$session_id, "abc-123")
})

test_that("ca_output json with NULL session_id uses NA", {
  skip_if_not_installed("jsonlite")
  out <- capture.output(
    codeagent:::.ca_format_output("hi", output_fmt = "json", session_id = NULL)
  )
  parsed <- jsonlite::fromJSON(paste(out, collapse = ""))
  expect_equal(parsed$response, "hi")
})

# ---------------------------------------------------------------------------
# sessions subcommand dispatch (new in plan #21)
# ---------------------------------------------------------------------------

test_that(".ca_dispatch sessions list", {
  r <- codeagent:::.ca_dispatch(c("sessions", "list"))
  expect_equal(r$cmd, "sessions")
  expect_equal(r$rest, "list")
})

test_that(".ca_dispatch sessions resume", {
  r <- codeagent:::.ca_dispatch(c("sessions", "resume", "abc123"))
  expect_equal(r$cmd, "sessions")
})

test_that(".ca_dispatch sessions delete", {
  r <- codeagent:::.ca_dispatch(c("sessions", "delete", "abc123"))
  expect_equal(r$cmd, "sessions")
})
