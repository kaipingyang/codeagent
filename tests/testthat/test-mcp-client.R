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


test_that("MCP client refuses unsupported mcptools versions", {
  testthat::local_mocked_bindings(
    .mcptools_supported = function(...) FALSE,
    .package = "codeagent")
  expect_warning(
    out <- mcp_client_tools(list(mcpServers = list())),
    "mcptools >= 1.0.2.9000")
  expect_equal(out, list())
})

test_that("r_mcp_server child expression enforces version and safe default", {
  cfg <- r_mcp_server(rscript = Sys.which("Rscript"))
  code <- paste(cfg$args, collapse = " ")
  expect_match(code, "1.0.2.9000", fixed = TRUE)
  expect_match(code, "session_tools = FALSE", fixed = TRUE)
})


test_that("mcp_client_tools accepts documented inline list config", {
  skip_if_not_installed("mcptools", minimum_version = "1.0.2.9000")
  expect_equal(mcp_client_tools(list(mcpServers = list())), list())
})
