# tests/testthat/test-tool_display.R
# Unit tests for the typed tool-result display contract + render dispatcher.

.tdv <- function(x) {
  if (S7::S7_inherits(x, ellmer::ContentToolResult)) as.character(x@value)
  else as.character(x)
}
.html <- function(tag) as.character(htmltools::tagList(tag))

# ---------------------------------------------------------------------------
# .tool_result2 contract
# ---------------------------------------------------------------------------

test_that(".tool_result2 returns ContentToolResult with card kind + unchanged value", {
  r <- codeagent:::.tool_result2("the value", kind = "text",
                                 payload = list(text = "the value"))
  expect_true(S7::S7_inherits(r, ellmer::ContentToolResult))
  expect_identical(as.character(r@value), "the value")
  expect_identical(r@extra$display$toolcard$kind, "text")
  expect_identical(r@extra$display$toolcard$status, "success")
})

test_that(".tool_result2 eagerly precomputes a right_output tag", {
  r <- codeagent:::.tool_result2("x", kind = "code",
                                 payload = list(text = "x<-1", lang = "r"))
  ro <- r@extra$display$right_output
  expect_true(inherits(ro, "shiny.tag") || inherits(ro, "shiny.tag.list"))
})

test_that(".tool_result2 sets in-chat html + full_screen, collapsed", {
  r <- codeagent:::.tool_result2("x", kind = "code",
                                 payload = list(text = "x<-1", lang = "r"))
  d <- r@extra$display
  expect_true(inherits(d$html, "shiny.tag") || inherits(d$html, "shiny.tag.list"))
  expect_true(isTRUE(d$full_screen))
  expect_false(isTRUE(d$open))
  fields <- names(shinychat:::get_tool_result_display(r))
  expect_true("html" %in% fields)
})

test_that("image toolbar has zoom+download but no separate fullscreen button", {
  d <- list(toolcard = list(kind = "image", status = "success",
            payload = list(images = list(list(mime = "image/png", b64 = "ABC")))))
  h <- .html(codeagent:::render_tool_output(d))
  expect_match(h, "data-toolcard-zoom")
  expect_match(h, "data-toolcard-download")
  expect_false(grepl("data-toolcard-fullscreen", h))
  expect_match(h, 'type="button"', fixed = TRUE)
})

test_that(".tool_result legacy wrapper still works", {
  r <- codeagent:::.tool_result("legacy", title = "T", markdown = "**md**")
  expect_true(S7::S7_inherits(r, ellmer::ContentToolResult))
  expect_identical(as.character(r@value), "legacy")
})

# ---------------------------------------------------------------------------
# render_tool_output per kind
# ---------------------------------------------------------------------------

test_that("render_tool_output: code kind renders highlighted pre + copy", {
  d <- list(toolcard = list(kind = "code", status = "success",
                      payload = list(text = "x<-1", lang = "r", filename = "a.R")))
  h <- .html(codeagent:::render_tool_output(d))
  expect_match(h, "language-r")
  expect_match(h, "data-toolcard-copy")
  expect_match(h, "toolcard")
})

test_that("render_tool_output: image kind embeds base64 + zoom toolbar", {
  d <- list(toolcard = list(kind = "image", status = "success",
                      payload = list(images = list(list(mime = "image/png", b64 = "ABC")))))
  h <- .html(codeagent:::render_tool_output(d))
  expect_match(h, "data:image/png;base64,ABC", fixed = TRUE)
  expect_match(h, "data-toolcard-zoom")
  expect_match(h, "toolcard-zoomable")
})

test_that("render_tool_output: diff kind colors added + deleted lines", {
  d <- list(toolcard = list(kind = "diff", status = "success",
                      payload = list(old = "a\nb\nc", new = "a\nB\nc",
                                     path = "/x/f.R", verb = "Edited")))
  h <- .html(codeagent:::render_tool_output(d))
  expect_match(h, "toolcard-diff-add")
  expect_match(h, "toolcard-diff-del")
})

test_that("render_tool_output: table kind renders reactable or html table", {
  skip_if_not_installed("reactable")
  d <- list(toolcard = list(kind = "table", status = "success",
                      payload = list(df = head(mtcars, 3))))
  h <- .html(codeagent:::render_tool_output(d))
  expect_match(h, "reactable|toolcard-html-table")
})

test_that("render_tool_output: error kind renders styled error box", {
  d <- list(toolcard = list(kind = "error", status = "error",
                      payload = list(message = "boom")))
  h <- .html(codeagent:::render_tool_output(d))
  expect_match(h, "toolcard-error-box")
  expect_match(h, "boom")
  expect_match(h, "toolcard-status-error")
})

# ---------------------------------------------------------------------------
# Backward-compat fallback
# ---------------------------------------------------------------------------

test_that("render_tool_output falls back to right_output when no card", {
  ro <- htmltools::tags$div(class = "legacy-ro", "hi")
  d  <- list(right_output = ro)
  h  <- .html(codeagent:::render_tool_output(d))
  expect_match(h, "legacy-ro")
})

test_that("render_tool_output falls back to markdown when no card/right_output", {
  d <- list(markdown = "**bold**")
  h <- .html(codeagent:::render_tool_output(d))
  expect_match(h, "<strong>bold</strong>")
})

# ---------------------------------------------------------------------------
# .adapt_tool_result
# ---------------------------------------------------------------------------

test_that(".adapt_tool_result types a bare ContentToolResult (raw btw sim)", {
  bare <- ellmer::ContentToolResult(value = "some output")
  ad   <- codeagent:::.adapt_tool_result(bare)
  expect_true(ad@extra$display$toolcard$kind %in%
              c("code", "image", "table", "diff", "text", "error"))
  expect_identical(as.character(ad@value), "some output")
})

test_that(".adapt_tool_result is idempotent on already-typed results", {
  r  <- codeagent:::.tool_result2("x", kind = "code",
                                  payload = list(text = "x", lang = "r"))
  r2 <- codeagent:::.adapt_tool_result(r)
  expect_identical(r2@extra$display$toolcard$kind, r@extra$display$toolcard$kind)
})

# ---------------------------------------------------------------------------
# .line_diff
# ---------------------------------------------------------------------------

test_that(".line_diff detects add/del/ctx", {
  d <- codeagent:::.line_diff("a\nb\nc", "a\nB\nc")
  types <- vapply(d, function(x) x$type, character(1))
  expect_true("add" %in% types)
  expect_true("del" %in% types)
  expect_true("ctx" %in% types)
})
