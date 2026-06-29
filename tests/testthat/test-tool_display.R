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

test_that(".tool_result2 returns ContentToolResult with ca kind + unchanged value", {
  r <- codeagent:::.tool_result2("the value", kind = "text",
                                 payload = list(text = "the value"))
  expect_true(S7::S7_inherits(r, ellmer::ContentToolResult))
  expect_identical(as.character(r@value), "the value")
  expect_identical(r@extra$display$ca$kind, "text")
  expect_identical(r@extra$display$ca$status, "success")
})

test_that(".tool_result2 eagerly precomputes a right_output tag", {
  r <- codeagent:::.tool_result2("x", kind = "code",
                                 payload = list(text = "x<-1", lang = "r"))
  ro <- r@extra$display$right_output
  expect_true(inherits(ro, "shiny.tag") || inherits(ro, "shiny.tag.list"))
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
  d <- list(ca = list(kind = "code", status = "success",
                      payload = list(text = "x<-1", lang = "r", filename = "a.R")))
  h <- .html(codeagent:::render_tool_output(d))
  expect_match(h, "language-r")
  expect_match(h, "data-ca-copy")
  expect_match(h, "ca-card")
})

test_that("render_tool_output: image kind embeds base64 + zoom toolbar", {
  d <- list(ca = list(kind = "image", status = "success",
                      payload = list(images = list(list(mime = "image/png", b64 = "ABC")))))
  h <- .html(codeagent:::render_tool_output(d))
  expect_match(h, "data:image/png;base64,ABC", fixed = TRUE)
  expect_match(h, "data-ca-zoom")
  expect_match(h, "ca-zoomable")
})

test_that("render_tool_output: diff kind colors added + deleted lines", {
  d <- list(ca = list(kind = "diff", status = "success",
                      payload = list(old = "a\nb\nc", new = "a\nB\nc",
                                     path = "/x/f.R", verb = "Edited")))
  h <- .html(codeagent:::render_tool_output(d))
  expect_match(h, "ca-diff-add")
  expect_match(h, "ca-diff-del")
})

test_that("render_tool_output: table kind renders reactable or html table", {
  skip_if_not_installed("reactable")
  d <- list(ca = list(kind = "table", status = "success",
                      payload = list(df = head(mtcars, 3))))
  h <- .html(codeagent:::render_tool_output(d))
  expect_match(h, "reactable|ca-html-table")
})

test_that("render_tool_output: error kind renders styled error box", {
  d <- list(ca = list(kind = "error", status = "error",
                      payload = list(message = "boom")))
  h <- .html(codeagent:::render_tool_output(d))
  expect_match(h, "ca-error-box")
  expect_match(h, "boom")
  expect_match(h, "ca-status-error")
})

# ---------------------------------------------------------------------------
# Backward-compat fallback
# ---------------------------------------------------------------------------

test_that("render_tool_output falls back to right_output when no ca", {
  ro <- htmltools::tags$div(class = "legacy-ro", "hi")
  d  <- list(right_output = ro)
  h  <- .html(codeagent:::render_tool_output(d))
  expect_match(h, "legacy-ro")
})

test_that("render_tool_output falls back to markdown when no ca/right_output", {
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
  expect_true(ad@extra$display$ca$kind %in%
              c("code", "image", "table", "diff", "text", "error"))
  expect_identical(as.character(ad@value), "some output")
})

test_that(".adapt_tool_result is idempotent on already-typed results", {
  r  <- codeagent:::.tool_result2("x", kind = "code",
                                  payload = list(text = "x", lang = "r"))
  r2 <- codeagent:::.adapt_tool_result(r)
  expect_identical(r2@extra$display$ca$kind, r@extra$display$ca$kind)
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
