# @path/to/file inline imports inside CLAUDE.md-style files (P4 backlog item):
# a line consisting ONLY of `@` + a path inlines that file's content. Claude
# Code's own convention; codeagent's `.load_claude_md()` previously ignored it
# entirely. `.expand_claude_md_imports()` is the standalone regex-scan +
# recursive-read helper; `.load_claude_md()` wires it into the existing
# candidate-file loop, sharing its `seen` set for cycle/dedup protection.

test_that("a whole-line @path import is inlined", {
  d <- withr::local_tempdir()
  writeLines(c("root:", "@sub.md", "after-import"), file.path(d, "CLAUDE.md"))
  writeLines("sub content line", file.path(d, "sub.md"))

  out <- .expand_claude_md_imports(
    paste(readLines(file.path(d, "CLAUDE.md")), collapse = "\n"), d, character(0))

  expect_true(grepl("sub content line", out$text, fixed = TRUE))
  expect_true(grepl("after-import", out$text, fixed = TRUE))
  expect_true(any(grepl("sub\\.md$", out$seen)))
})

test_that("an inline (non-whole-line) @ is left untouched, not treated as an import", {
  d <- withr::local_tempdir()
  out <- .expand_claude_md_imports(
    "contact me @foo.bar or see user@example.com", d, character(0))
  expect_identical(out$text, "contact me @foo.bar or see user@example.com")
})

test_that("an @import of a missing file reports rather than errors", {
  d <- withr::local_tempdir()
  out <- .expand_claude_md_imports("@does-not-exist.md", d, character(0))
  expect_true(grepl("not found", out$text))
  expect_false(any(grepl("does-not-exist", out$seen)))
})

test_that("a mutual-reference cycle terminates instead of recursing forever", {
  d <- withr::local_tempdir()
  writeLines(c("A start", "@b.md"), file.path(d, "a.md"))
  writeLines(c("B start", "@a.md"), file.path(d, "b.md"))

  out <- .expand_claude_md_imports(
    paste(readLines(file.path(d, "a.md")), collapse = "\n"), d, character(0))

  expect_true(grepl("A start", out$text, fixed = TRUE))
  expect_true(grepl("B start", out$text, fixed = TRUE))
  expect_true(grepl("already loaded / cycle", out$text))
})

test_that("max_depth stops a long distinct-file import chain", {
  d <- withr::local_tempdir()
  # Seven-file chain: f0 -> f1 -> ... -> f6 (6 hops). default max_depth = 5
  # blocks the 6th hop (f5 -> f6) before f6's content is ever read.
  for (i in 6:1)
    writeLines(sprintf("@f%d.md", i), file.path(d, sprintf("f%d.md", i - 1L)))
  writeLines("BOTTOM_MARKER", file.path(d, "f6.md"))

  out <- .expand_claude_md_imports(
    paste(readLines(file.path(d, "f0.md")), collapse = "\n"), d, character(0))
  expect_false(grepl("BOTTOM_MARKER", out$text, fixed = TRUE))
  expect_true(grepl("max depth", out$text))
})

test_that("~ and absolute paths resolve outside base_dir", {
  d <- withr::local_tempdir()
  abs_target <- file.path(d, "elsewhere.md")
  writeLines("elsewhere content", abs_target)

  sub_dir <- file.path(d, "nested")
  dir.create(sub_dir)
  out <- .expand_claude_md_imports(
    sprintf("@%s", abs_target), sub_dir, character(0))
  expect_true(grepl("elsewhere content", out$text, fixed = TRUE))
})

test_that(".load_claude_md() expands @imports found in a project CLAUDE.md", {
  d <- withr::local_tempdir()
  writeLines(c("Project rules:", "@shared-rule.md"), file.path(d, "CLAUDE.md"))
  writeLines("SHARED_RULE_MARKER", file.path(d, "shared-rule.md"))

  res <- .load_claude_md(d)
  expect_true(!is.null(res))
  expect_true(grepl("SHARED_RULE_MARKER", res, fixed = TRUE))
})
