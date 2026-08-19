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
  expect_identical(r@extra$codeagent$artifact$kind, "text")
  expect_identical(r@extra$codeagent$artifact$status, "success")
  # private fields must NOT be under extra$display (shinychat would warn)
  expect_null(r@extra$display$toolcard)
  expect_null(r@extra$display$right_output)
})

test_that(".tool_result2 stores artifact data source on extra$codeagent (no right_output)", {
  r <- codeagent:::.tool_result2("x", kind = "code",
                                 payload = list(text = "x<-1", lang = "r"))
  art <- r@extra$codeagent$artifact
  expect_identical(art$kind, "code")
  expect_identical(art$payload$text, "x<-1")
  # right panel re-renders from the artifact -> no stored right_output field
  expect_null(r@extra$display$right_output)
  # render_artifact(artifact) produces the panel view tag on demand
  tag <- codeagent:::render_artifact(art, mode = "panel")
  expect_true(inherits(tag, "shiny.tag") || inherits(tag, "shiny.tag.list"))
})

test_that(".tool_result2 sets in-chat html + full_screen, collapsed", {
  r <- codeagent:::.tool_result2("x", kind = "code",
                                 payload = list(text = "x<-1", lang = "r"))
  d <- r@extra$display
  expect_true(inherits(d$html, "shiny.tag") || inherits(d$html, "shiny.tag.list"))
  expect_true(isTRUE(d$full_screen))
  expect_false(isTRUE(d$open))
  # display carries only shinychat-official fields (html present, no private keys)
  expect_true("html" %in% names(d))
  expect_null(d$toolcard)
})

test_that("image toolbar has zoom, download, and fullscreen buttons", {
  d <- list(toolcard = list(kind = "image", status = "success",
            payload = list(images = list(list(mime = "image/png", b64 = "ABC")))))
  h <- .html(codeagent:::render_artifact(d))
  expect_match(h, "data-toolcard-zoom")
  expect_match(h, "data-toolcard-download")
  expect_match(h, "data-toolcard-fullscreen")
})

test_that(".tool_result legacy wrapper still works", {
  r <- codeagent:::.tool_result("legacy", title = "T", markdown = "**md**")
  expect_true(S7::S7_inherits(r, ellmer::ContentToolResult))
  expect_identical(as.character(r@value), "legacy")
})



test_that("tool displays use shinychat official constructor with useful previews", {
  r <- codeagent:::.tool_result2(
    "first line\nsecond line", kind = "text", title = "Read file.R",
    payload = list(text = "first line\nsecond line"))
  expect_s3_class(r@extra$display, "shinychat_tool_result_display")
  expect_identical(r@extra$display$label, "Read file.R")
  expect_identical(r@extra$display$value_preview, "first line second line")
})

test_that("display constructor feature-detect falls back to validated official fields", {
  testthat::local_mocked_bindings(
    .shinychat_tool_result_constructor = function() NULL
  )
  d <- codeagent:::.new_tool_result_display(
    title = "T", label = "L", value_preview = "V", open = FALSE)
  expect_type(d, "list")
  expect_named(d, c("title", "show_request", "open", "full_screen", "label",
                    "value_preview"), ignore.order = TRUE)
  expect_null(d$toolcard)
})

test_that("raw btw footer survives normalization and recognizable patches become diff", {
  footer <- htmltools::tags$span("btw footer")
  raw <- ellmer::ContentToolResult(
    value = "diff --git a/a.R b/a.R\n@@ -1 +1 @@\n-old\n+new",
    extra = list(display = list(title = "Patch", footer = footer)))
  adapted <- codeagent:::.adapt_tool_result(raw)
  expect_identical(adapted@extra$codeagent$artifact$kind, "diff")
  expect_identical(as.character(adapted@extra$display$footer),
                   as.character(footer))
  expect_match(adapted@extra$display$value_preview, "diff --git", fixed = TRUE)
})
# ---------------------------------------------------------------------------
# render_artifact per kind
# ---------------------------------------------------------------------------

test_that("render_artifact: code kind renders highlighted pre + copy", {
  d <- list(toolcard = list(kind = "code", status = "success",
                      payload = list(text = "x<-1", lang = "r", filename = "a.R")))
  h <- .html(codeagent:::render_artifact(d))
  expect_match(h, "language-r")
  expect_match(h, "data-toolcard-copy")
  expect_match(h, "toolcard")
})

test_that("render_artifact: image kind embeds base64 + zoom toolbar", {
  d <- list(toolcard = list(kind = "image", status = "success",
                      payload = list(images = list(list(mime = "image/png", b64 = "ABC")))))
  h <- .html(codeagent:::render_artifact(d))
  expect_match(h, "data:image/png;base64,ABC", fixed = TRUE)
  expect_match(h, "data-toolcard-zoom")
  expect_match(h, "toolcard-zoomable")
})

test_that("render_artifact: diff kind colors added + deleted lines", {
  d <- list(toolcard = list(kind = "diff", status = "success",
                      payload = list(old = "a\nb\nc", new = "a\nB\nc",
                                     path = "/x/f.R", verb = "Edited")))
  h <- .html(codeagent:::render_artifact(d))
  expect_match(h, "toolcard-diff-add")
  expect_match(h, "toolcard-diff-del")
})

test_that("render_artifact: table kind renders reactable or html table", {
  skip_if_not_installed("reactable")
  d <- list(toolcard = list(kind = "table", status = "success",
                      payload = list(df = head(mtcars, 3))))
  h <- .html(codeagent:::render_artifact(d))
  expect_match(h, "reactable|toolcard-html-table")
})

test_that("render_artifact: error kind renders styled error box", {
  d <- list(toolcard = list(kind = "error", status = "error",
                      payload = list(message = "boom")))
  h <- .html(codeagent:::render_artifact(d))
  expect_match(h, "toolcard-error-box")
  expect_match(h, "boom")
  expect_match(h, "toolcard-status-error")
})

# ---------------------------------------------------------------------------
# Backward-compat fallback
# ---------------------------------------------------------------------------

test_that("render_artifact falls back to markdown when no card", {
  d <- list(markdown = "**bold**")
  h <- .html(codeagent:::render_artifact(d))
  expect_match(h, "<strong>bold</strong>")
})

# ---------------------------------------------------------------------------
# .adapt_tool_result
# ---------------------------------------------------------------------------

test_that(".adapt_tool_result types a bare ContentToolResult (raw btw sim)", {
  bare <- ellmer::ContentToolResult(value = "some output")
  ad   <- codeagent:::.adapt_tool_result(bare)
  expect_true(ad@extra$codeagent$artifact$kind %in%
              c("code", "image", "table", "diff", "text", "error"))
  expect_identical(as.character(ad@value), "some output")
})

test_that(".adapt_tool_result is idempotent on already-typed results", {
  r  <- codeagent:::.tool_result2("x", kind = "code",
                                  payload = list(text = "x", lang = "r"))
  r2 <- codeagent:::.adapt_tool_result(r)
  expect_identical(r2@extra$codeagent$artifact$kind, r@extra$codeagent$artifact$kind)
})

test_that(".adapt_tool_result migrates a legacy extra$display$toolcard card", {
  # Pre-migration session: typed card sat under extra$display$toolcard, which
  # shinychat now warns on. The adapter must promote it to extra$codeagent and
  # strip the private keys so the restored session renders warning-free.
  leg <- ellmer::ContentToolResult(value = "x", extra = list(display = list(
    title = "Old", right_output = "junk",
    toolcard = list(kind = "code", status = "success",
                    payload = list(text = "1+1", lang = "r")))))
  ad <- codeagent:::.adapt_tool_result(leg)
  expect_identical(ad@extra$codeagent$artifact$kind, "code")
  expect_null(ad@extra$display$toolcard)
  expect_null(ad@extra$display$right_output)
  expect_true("html" %in% names(ad@extra$display))
  # second pass is a no-op (already migrated)
  ad2 <- codeagent:::.adapt_tool_result(ad)
  expect_identical(ad2@extra$codeagent$artifact$kind, "code")
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

test_that(".artifact_title strips HTML and follows the fallback chain", {
  # Plain title with markup -> tags stripped.
  expect_equal(
    codeagent:::.artifact_title(list(title = "<b>Read</b> file.R")),
    "Read file.R"
  )
  # Falls back to toolcard$title when top-level title is absent.
  expect_equal(
    codeagent:::.artifact_title(list(toolcard = list(title = "<i>Bash</i>"))),
    "Bash"
  )
  # Nothing usable -> "Output".
  expect_equal(codeagent:::.artifact_title(NULL), "Output")
  expect_equal(codeagent:::.artifact_title(list()), "Output")
})


test_that("official display survives shinychat contents conversion without warnings", {
  tool <- ellmer::tool(function(x) x, name = "fixture_tool",
                       description = "fixture",
                       arguments = list(x = ellmer::type_string("x")))
  request <- ellmer::ContentToolRequest(
    id = "display-1", name = "fixture_tool", arguments = list(x = "x"),
    tool = tool)
  result <- codeagent:::.adapt_tool_result(ellmer::ContentToolResult(
    value = "fixture output", request = request,
    extra = list(display = list(title = "Fixture"))))
  chat <- ellmer::chat_anthropic(model = "fixture")
  expect_identical(result@request@id, "display-1")
  chat$register_tool(tool)
  chat$set_turns(list(
    ellmer::Turn("assistant", contents = list(request)),
    ellmer::Turn("user", contents = list(result))))
  items <- expect_no_warning(shinychat::contents_shinychat(chat))
  expect_length(items, 1L)
})
