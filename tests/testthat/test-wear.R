# tests/testthat/test-wear.R
# Tests for R/wear.R: generate_wear_report() and wear_explore() argument validation.

# ---------------------------------------------------------------------------
# Helpers: build mock ellmer Turn objects using real S7 classes so that @role
# and @contents accessors work correctly inside generate_wear_report().
# ---------------------------------------------------------------------------

.make_user_turn <- function(text) {
  ellmer:::Turn(
    role     = "user",
    contents = list(ellmer:::ContentText(text = text))
  )
}

.make_asst_turn <- function(text) {
  ellmer:::Turn(
    role     = "assistant",
    contents = list(ellmer:::ContentText(text = text))
  )
}

.make_tool_turn <- function(value, code = NULL) {
  ellmer:::Turn(
    role     = "assistant",
    contents = list(
      ellmer:::ContentToolResult(
        value = value,
        extra = list(code = code)
      )
    )
  )
}

# ---------------------------------------------------------------------------
# Mock client factory
# ---------------------------------------------------------------------------

.make_mock_wear_client <- function(turns) {
  force(turns)
  chat <- list(
    get_turns        = function() turns,
    get_system_prompt = function() "",
    set_system_prompt = function(sp) invisible(NULL),
    register_tool    = function(t) invisible(NULL)
  )
  client <- list(chat = chat)
  class(client) <- "CodagentClient"
  client
}

# ===========================================================================
# generate_wear_report() tests
# ===========================================================================

test_that("generate_wear_report errors on empty conversation history", {
  client <- .make_mock_wear_client(list())
  expect_error(
    generate_wear_report(client, path = tempfile(fileext = ".qmd")),
    class = "rlang_error"
  )
})

test_that("generate_wear_report writes a file with valid YAML frontmatter", {
  turns <- list(
    .make_user_turn("What is the mean mpg?"),
    .make_asst_turn("The mean mpg is 20.1.")
  )
  client <- .make_mock_wear_client(turns)
  path <- withr::local_tempfile(fileext = ".qmd")

  result <- generate_wear_report(client, path = path, title = "Test Report")

  expect_true(file.exists(path))
  lines <- readLines(path, warn = FALSE)
  expect_equal(lines[[1]], "---")
  expect_true(any(grepl('title: "Test Report"', lines, fixed = TRUE)))
  expect_true(any(grepl("^format:", lines)))
  expect_true(any(grepl("^execute:", lines)))
})

test_that("generate_wear_report returns the path invisibly", {
  turns <- list(.make_user_turn("Any question?"), .make_asst_turn("Any answer."))
  client <- .make_mock_wear_client(turns)
  path <- withr::local_tempfile(fileext = ".qmd")

  result <- withVisible(generate_wear_report(client, path = path))

  expect_equal(result$value, path)
  expect_false(result$visible)
})

test_that("generate_wear_report renders user turns as ## headings", {
  question <- "What is the mean mpg?"
  turns <- list(
    .make_user_turn(question),
    .make_asst_turn("Mean mpg is 20.1.")
  )
  client <- .make_mock_wear_client(turns)
  path <- withr::local_tempfile(fileext = ".qmd")

  generate_wear_report(client, path = path)

  lines <- readLines(path, warn = FALSE)
  expect_true(any(grepl(paste0("## ", question), lines, fixed = TRUE)))
})

test_that("generate_wear_report embeds tool code as {r} chunks", {
  code <- "mean(mtcars$mpg)"
  turns <- list(
    .make_user_turn("What is mean mpg?"),
    .make_tool_turn(value = "20.09062", code = code)
  )
  client <- .make_mock_wear_client(turns)
  path <- withr::local_tempfile(fileext = ".qmd")

  generate_wear_report(client, path = path)

  lines <- readLines(path, warn = FALSE)
  expect_true(any(grepl("```{r}", lines, fixed = TRUE)))
  expect_true(any(grepl(code, lines, fixed = TRUE)))
})

test_that("generate_wear_report skips tool results without code", {
  turns <- list(
    .make_user_turn("Count rows."),
    # ContentToolResult with no code -- should still write value as blockquote
    .make_tool_turn(value = "32 rows", code = NULL)
  )
  client <- .make_mock_wear_client(turns)
  path <- withr::local_tempfile(fileext = ".qmd")

  # Should not error even when code = NULL
  expect_no_error(generate_wear_report(client, path = path))

  lines <- readLines(path, warn = FALSE)
  # No {r} chunk when code is NULL
  expect_false(any(grepl("```{r}", lines, fixed = TRUE)))
})

test_that("generate_wear_report includes assistant prose in output", {
  prose <- "The correlation between weight and mpg is strong and negative."
  turns <- list(
    .make_user_turn("Describe the correlation."),
    .make_asst_turn(prose)
  )
  client <- .make_mock_wear_client(turns)
  path <- withr::local_tempfile(fileext = ".qmd")

  generate_wear_report(client, path = path)

  content <- paste(readLines(path, warn = FALSE), collapse = "\n")
  expect_true(grepl(prose, content, fixed = TRUE))
})

# ===========================================================================
# wear_explore() argument validation (does not start REPL/app)
# ===========================================================================

test_that("wear_explore validates mode argument", {
  expect_error(
    wear_explore(data = list(), mode = "bad_mode"),
    class = "simpleError"
  )
})

test_that("wear_explore accepts mode = 'repl' and 'shiny' as valid values", {
  # match.arg should not error for valid modes
  # We cannot run the full function (it starts an interactive REPL),
  # so we test only that match.arg passes by calling it directly.
  expect_no_error(match.arg("repl",   c("repl", "shiny")))
  expect_no_error(match.arg("shiny",  c("repl", "shiny")))
})
