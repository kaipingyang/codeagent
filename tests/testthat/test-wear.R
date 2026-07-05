# Tests for the WEAR loop data-exploration report export (R/wear.R).

# Build a CodeagentClient-like stub wrapping a real ellmer chat with set turns.
.wear_fake_client <- function(turns = list()) {
  chat <- ellmer::chat_openai_compatible(base_url = "http://x", model = "m",
                                         credentials = function() "k")
  if (length(turns)) tryCatch(chat$set_turns(turns), error = function(e) NULL)
  structure(list(chat = chat), class = "CodeagentClient")
}

test_that("generate_wear_report errors on empty history", {
  client <- .wear_fake_client(list())
  expect_error(generate_wear_report(client, path = tempfile(fileext = ".qmd")),
               "No conversation history")
})

test_that("generate_wear_report writes a valid .qmd with headings and code chunks", {
  turns <- list(
    ellmer::Turn("user", list(ellmer::ContentText("What is the mean mpg?"))),
    ellmer::Turn("assistant", list(
      ellmer::ContentText("The mean mpg is about 20."),
      ellmer::ContentToolResult(value = "20.09",
                                extra = list(code = "mean(mtcars$mpg)"))
    ))
  )
  client <- .wear_fake_client(turns)
  path   <- tempfile(fileext = ".qmd")
  ret    <- suppressMessages(generate_wear_report(client, path = path,
                                                  title = "MT Analysis"))
  expect_identical(ret, path)
  expect_true(file.exists(path))
  txt <- paste(readLines(path), collapse = "\n")
  # YAML front-matter with title
  expect_true(grepl('title: "MT Analysis"', txt, fixed = TRUE))
  # user message -> ## heading
  expect_true(grepl("## What is the mean mpg?", txt, fixed = TRUE))
  # tool code -> {r} chunk
  expect_true(grepl("```{r}", txt, fixed = TRUE))
  expect_true(grepl("mean(mtcars$mpg)", txt, fixed = TRUE))
  unlink(path)
})

test_that("wear_explore validates the mode argument before doing anything", {
  # match.arg() rejects an invalid mode up front (no client built, no launch).
  expect_error(wear_explore(data = list(mtcars = mtcars), mode = "not-a-mode"),
               "should be one of")
})

test_that("codeagent already prefers ellmer::df_schema over the self-written fallback", {
  # Guard: ellmer provides df_schema(); tools_data.R uses it as the primary
  # path with .df_schema() only as a fallback. If ellmer drops it, flag here.
  expect_true(exists("df_schema", where = asNamespace("ellmer")))
})
