# tests/testthat/test-tools_data.R

library(ellmer)

# ---------------------------------------------------------------------------
# .df_schema
# ---------------------------------------------------------------------------

test_that(".df_schema returns a string with row/col info", {
  schema <- codeagent:::.df_schema(mtcars, "mtcars")
  expect_true(is.character(schema))
  expect_true(grepl("32", schema))   # 32 rows
  expect_true(grepl("11", schema))   # 11 cols
  expect_true(grepl("mtcars", schema))
  expect_true(grepl("mpg", schema))
})

test_that(".df_schema shows column types", {
  df <- data.frame(x = 1:3, y = c("a", "b", "c"), stringsAsFactors = FALSE)
  schema <- codeagent:::.df_schema(df, "df")
  expect_true(grepl("integer|numeric", schema, ignore.case = TRUE))
  expect_true(grepl("character", schema, ignore.case = TRUE))
})

test_that(".df_schema notes NA values", {
  df <- data.frame(x = c(1L, NA, 3L))
  schema <- codeagent:::.df_schema(df, "df")
  expect_true(grepl("NA", schema))
})

test_that(".df_schema handles empty data.frame", {
  schema <- codeagent:::.df_schema(data.frame(), "empty")
  expect_true(is.character(schema))
  expect_true(grepl("0", schema))
})

# ---------------------------------------------------------------------------
# explore_data_tool
# ---------------------------------------------------------------------------

test_that("explore_data_tool is a valid ellmer ToolDef", {
  t <- explore_data_tool(envir = new.env(parent = baseenv()))
  expect_true(inherits(t, "ellmer::ToolDef"))
})

test_that("explore_data_tool returns schema when called without code", {
  e <- new.env(parent = baseenv())
  e$mydf <- mtcars
  t <- explore_data_tool(envir = e)
  result <- t(data_name = "mydf")
  val <- tryCatch(as.character(result@value), error = function(e) "")
  expect_true(grepl("mydf|32|mpg", val, ignore.case = TRUE))
})

test_that("explore_data_tool errors cleanly on missing data.frame", {
  e <- new.env(parent = baseenv())
  t <- explore_data_tool(envir = e)
  result <- t(data_name = "nonexistent_df")
  val <- tryCatch(as.character(result@value), error = function(e) "")
  expect_true(grepl("not found|Error", val, ignore.case = TRUE))
})

test_that("explore_data_tool errors cleanly on non-data.frame object", {
  e <- new.env(parent = baseenv())
  e$x <- 1:10
  t <- explore_data_tool(envir = e)
  result <- t(data_name = "x")
  val <- tryCatch(as.character(result@value), error = function(e) "")
  expect_true(grepl("not a data.frame|Error", val, ignore.case = TRUE))
})

test_that("explore_data_tool executes dplyr/base code and returns result", {
  e <- new.env(parent = baseenv())
  e$mtcars <- mtcars
  t <- explore_data_tool(envir = e)
  # Simple base R query: count rows
  result <- t(data_name = "mtcars",
              question  = "How many rows?",
              code      = "nrow(mtcars)")
  val <- tryCatch(as.character(result@value), error = function(e) "")
  expect_true(grepl("32", val))
})

test_that("explore_data_tool does not modify the source data.frame", {
  e <- new.env(parent = baseenv())
  e$df <- data.frame(x = 1:3)
  t <- explore_data_tool(envir = e)
  result <- t(data_name = "df", question = "add column", code = "df$y <- 99; df")  # tries to add column
  # Original df in envir should be unchanged (exec runs in sub-env)
  expect_null(e$df$y)
})

test_that("explore_data_tool returns error result on bad code", {
  e <- new.env(parent = baseenv())
  e$df <- data.frame(x = 1:3)
  t <- explore_data_tool(envir = e)
  result <- t(data_name = "df", code = "stop('intentional error')")
  val <- tryCatch(as.character(result@value), error = function(e) "")
  expect_true(grepl("Error|intentional", val, ignore.case = TRUE))
})

# ---------------------------------------------------------------------------
# register_explore_data_tool
# ---------------------------------------------------------------------------

test_that("register_explore_data_tool adds ExploreData to the chat", {
  ch <- chat_anthropic(model = "claude-sonnet-4-6")
  register_explore_data_tool(ch)
  tool_names <- names(ch$get_tools())
  # tool may be registered as "ExploreData" or "tool_NNN"
  has_explore <- any(vapply(ch$get_tools(), function(t) {
    tryCatch(t@annotations$title == "ExploreData", error = function(e) FALSE)
  }, logical(1)))
  expect_true(has_explore)
})
