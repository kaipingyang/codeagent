test_that("lint_tool + format_tool build named ellmer tools", {
  expect_identical(lint_tool()@name, "Lint")
  expect_identical(format_tool()@name, "Format")
})

test_that("register_lint_tools registers Lint + Format", {
  chat <- ellmer::chat_openai_compatible(
    base_url = "http://x", model = "m", credentials = function() "k")
  register_lint_tools(chat)
  nms <- vapply(chat$get_tools(), function(t) t@name, character(1))
  expect_true(all(c("Lint", "Format") %in% nms))
})

test_that(".lint_impl flags issues and passes clean files", {
  skip_if_not_installed("lintr")
  bad <- tempfile(fileext = ".R"); on.exit(unlink(bad), add = TRUE)
  writeLines("x = 1", bad)  # '=' assignment triggers a default lintr lint
  res <- .lint_impl(bad)
  expect_s3_class(res, "ellmer::ContentToolResult")
  expect_match(tolower(as.character(res@value)), "lint")

  good <- tempfile(fileext = ".R"); on.exit(unlink(good), add = TRUE)
  writeLines("x <- 1L\n", good)
  res2 <- .lint_impl(good)
  expect_s3_class(res2, "ellmer::ContentToolResult")
})

test_that(".format_impl reformats a messy file with styler", {
  skip_if_not_installed("styler")
  f <- tempfile(fileext = ".R"); on.exit(unlink(f), add = TRUE)
  writeLines("f<-function(x){x+1}", f)
  res <- .format_impl(f)
  expect_s3_class(res, "ellmer::ContentToolResult")
  formatted <- paste(readLines(f), collapse = "\n")
  expect_match(formatted, "<- function")  # styler spaced the assignment
})

test_that("verify_r_lints returns a compatible verify_fn", {
  vf <- verify_r_lints(path = "R")
  expect_true(is.function(vf))
  out <- vf("response", NULL, tempdir())
  expect_true(is.list(out) && is.logical(out$passed))
})
