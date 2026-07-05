# tests/testthat/test-mcp-client.R
# Tests for the MCP client wrapper (M8). Graceful handling without a live
# MCP server (real stdio connections require external processes).

library(ellmer)

test_that("register_mcp_client with NULL config registers nothing", {
  ch <- chat_anthropic(model = "claude-sonnet-4-6")
  expect_equal(register_mcp_client(ch, NULL), 0L)
})

test_that("register_mcp_client handles a missing config file gracefully", {
  skip_if_not_installed("mcptools")
  ch <- chat_anthropic(model = "claude-sonnet-4-6")
  expect_equal(suppressWarnings(register_mcp_client(ch, "/no/such/mcp.json")), 0L)
})

test_that("mcp_client_tools returns a list (never errors)", {
  skip_if_not_installed("mcptools")
  out <- suppressWarnings(mcp_client_tools("/no/such/mcp.json"))
  expect_true(is.list(out))
})

test_that("codeagent_client accepts mcp_config without registering on NULL", {
  ch  <- chat_anthropic(model = "claude-sonnet-4-6")
  cli <- codeagent_client(ch, permission_mode = "bypass",
                          btw_groups = NULL, mcp_config = NULL, cwd = getwd())
  expect_s3_class(cli, "CodeagentClient")
})
