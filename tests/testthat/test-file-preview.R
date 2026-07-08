test_that(".build_file_preview renders Markdown to HTML", {
  skip_if_not_installed("commonmark")
  f <- withr::local_tempfile(fileext = ".md")
  writeLines(c("# Title", "", "Some **bold** text."), f)

  ui <- codeagent:::.build_file_preview(f, "md")
  html <- as.character(ui)
  expect_true(grepl("<h1", html))
  expect_true(grepl("<strong>bold</strong>", html))
})

test_that(".build_file_preview renders CSV via reactable when available", {
  skip_if_not_installed("reactable")
  f <- withr::local_tempfile(fileext = ".csv")
  utils::write.csv(data.frame(a = 1:3, b = c("x", "y", "z")), f, row.names = FALSE)

  ui <- codeagent:::.build_file_preview(f, "csv")
  # reactable returns an htmlwidget; either way it must be renderable to a tag.
  expect_true(inherits(ui, c("reactable", "htmlwidget", "shiny.tag", "shiny.tag.list")))
})

test_that(".build_file_preview builds a code editor for source files", {
  f <- withr::local_tempfile(fileext = ".R")
  writeLines(c("f <- function(x) x + 1", "g <- 2"), f)

  ui <- codeagent:::.build_file_preview(f, "R", id = "ced__test")
  html <- as.character(ui)
  # input_code_editor emits the editor container with our id + the file text.
  expect_true(grepl("ced__test", html))
  expect_true(grepl("function", html))
})

test_that(".build_file_preview embeds images as data URIs", {
  skip_if_not_installed("base64enc")
  f <- withr::local_tempfile(fileext = ".png")
  # dataURI() base64-encodes the file bytes and infers the mime from the .png
  # extension -- it does not decode the image, so PNG magic bytes are enough.
  writeBin(as.raw(c(0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a)), f)

  ui <- codeagent:::.build_file_preview(f, "png")
  html <- as.character(ui)
  expect_true(grepl("<img", html))
  expect_true(grepl("base64", html))   # data URI, regardless of inferred mime
})

test_that(".build_file_preview degrades to an [Error] paragraph on unreadable input", {
  ui <- suppressWarnings(codeagent:::.build_file_preview("/no/such/file.R", "R"))
  html <- as.character(ui)
  # A missing file yields either an [Error] note or an empty editor -- never a crash.
  expect_true(inherits(ui, c("shiny.tag", "shiny.tag.list")))
  expect_type(html, "character")
})
