# tests/testthat/test-addin.R

# ---------------------------------------------------------------------------
# .get_editor_selection -- graceful degradation
# ---------------------------------------------------------------------------

test_that(".get_editor_selection returns NULL when rstudioapi not available", {
  # In testthat (non-interactive, no IDE), rstudioapi::getSourceEditorContext
  # either throws or returns no selection. Both should yield NULL.
  result <- codeagent:::.get_editor_selection()
  # NULL or empty character -- never throws
  expect_true(is.null(result) || identical(result, character(0)))
})

# ---------------------------------------------------------------------------
# codeagent_addin -- non-interactive guard
# ---------------------------------------------------------------------------

test_that("codeagent_addin_selection does not error in non-interactive session", {
  # rstudioapi is absent / returns nothing in testthat; the addin should not
  # throw -- it should silently build a client (which may fail on missing key,
  # but the selection-reading part should succeed/return NULL gracefully).
  # We only test that .get_editor_selection doesn't throw.
  expect_no_error(codeagent:::.get_editor_selection())
})

# ---------------------------------------------------------------------------
# .insert_at_cursor -- no-op when rstudioapi absent
# ---------------------------------------------------------------------------

test_that(".insert_at_cursor is a no-op when rstudioapi not available", {
  # Should return invisibly NULL without throwing.
  expect_no_error(codeagent:::.insert_at_cursor("some text"))
  result <- codeagent:::.insert_at_cursor("some text")
  expect_null(result)
})

# ---------------------------------------------------------------------------
# Addin exports
# ---------------------------------------------------------------------------

test_that("codeagent_addin and codeagent_addin_selection are exported", {
  exports <- getNamespaceExports("codeagent")
  expect_true("codeagent_addin" %in% exports)
  expect_true("codeagent_addin_selection" %in% exports)
})

test_that("addins.dcf exists and lists both addins", {
  f <- system.file("rstudio", "addins.dcf", package = "codeagent")
  skip_if(nchar(f) == 0, "addins.dcf not in installed package (source only)")
  lines <- readLines(f, warn = FALSE)
  expect_true(any(grepl("codeagent_addin", lines)))
  expect_true(any(grepl("codeagent_addin_selection", lines)))
})
