# tests/testthat/test-tool_run_r.R
# Unit tests for the permission-gated RunR tool.

.tool_val <- function(x) {
  if (S7::S7_inherits(x, ellmer::ContentToolResult)) as.character(x@value)
  else if (is.character(x)) x
  else tryCatch(as.character(x), error = function(e) format(x))
}

test_that("RunR resolves to 'ask' in default mode (gated)", {
  expect_equal(check_permission("RunR", "default"), "ask")
})

test_that("RunR is denied in plan mode (non-readonly)", {
  expect_equal(check_permission("RunR", "plan"), "deny")
})

test_that("RunR is denied in dont_ask mode", {
  expect_equal(check_permission("RunR", "dont_ask"), "deny")
})

test_that("RunR is allowed in bypass mode", {
  expect_equal(check_permission("RunR", "bypass"), "allow")
})

test_that("run_r_tool builds with correct name + destructive annotation", {
  skip_if_not_installed("btw")
  t <- run_r_tool(mode = "default")
  expect_true(inherits(t, "ellmer::ToolDef"))
  expect_identical(t@name, "RunR")
  expect_true(isTRUE(t@annotations$destructive_hint))
  expect_false(isTRUE(t@annotations$read_only_hint))
})

test_that("RunR denies execution when ask_fn returns FALSE", {
  skip_if_not_installed("btw")
  deny_fn <- function(tool_name, input) FALSE
  t <- run_r_tool(mode = "default", ask_fn = deny_fn)
  res <- t(code = "stop('should not run')", `_intent` = "test")
  expect_match(.tool_val(res), "Permission denied")
})

test_that("RunR executes when ask_fn returns TRUE", {
  skip_if_not_installed("btw")
  allow_fn <- function(tool_name, input) TRUE
  t <- run_r_tool(mode = "default", ask_fn = allow_fn)
  res <- t(code = "1 + 1", `_intent` = "test")
  # btw returns a list of Content objects; verify it ran (no denial text)
  txt <- paste(vapply(if (is.list(res)) res else list(res),
                      function(x) .tool_val(x), character(1)), collapse = " ")
  expect_false(grepl("Permission denied", txt))
})

test_that("RunR executes directly in bypass mode (no ask_fn needed)", {
  skip_if_not_installed("btw")
  t <- run_r_tool(mode = "bypass")
  res <- t(code = "2 * 3", `_intent` = "test")
  txt <- paste(vapply(if (is.list(res)) res else list(res),
                      function(x) .tool_val(x), character(1)), collapse = " ")
  expect_false(grepl("Permission denied", txt))
})

test_that("RunR transforms btw result into codeagent display contract", {
  skip_if_not_installed("btw")
  t <- run_r_tool(mode = "bypass")
  res <- t(code = "1:5", `_intent` = "test")
  expect_true(S7::S7_inherits(res, ellmer::ContentToolResult))
  disp <- res@extra$display
  expect_true(all(c("title", "markdown", "right_output") %in% names(disp)))
  expect_match(disp$markdown, "```r", fixed = TRUE)
})

test_that("RunR embeds plot as base64 img in right_output", {
  skip_if_not_installed("btw")
  t <- run_r_tool(mode = "bypass")
  res <- t(code = "plot(1:10)", `_intent` = "test")
  ro <- as.character(res@extra$display$right_output)
  expect_true(grepl("data:image", ro, fixed = TRUE))
  # LLM value notes the plot
  expect_match(.tool_val(res), "plot")
})

test_that("RunR captures error text from btw ContentError", {
  skip_if_not_installed("btw")
  t <- run_r_tool(mode = "bypass")
  res <- t(code = "stop('boom')", `_intent` = "test")
  expect_match(.tool_val(res), "boom")
})
