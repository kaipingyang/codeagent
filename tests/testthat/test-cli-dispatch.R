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
