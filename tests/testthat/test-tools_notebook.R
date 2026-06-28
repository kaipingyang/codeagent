# tests/testthat/test-tools_notebook.R
# Unit tests for NotebookEdit / NotebookRead tools.

# ---------------------------------------------------------------------------
# Helper: create a minimal valid .ipynb notebook
# ---------------------------------------------------------------------------

.make_ipynb <- function(path, n_cells = 3L) {
  cells <- lapply(seq_len(n_cells), function(i) {
    list(
      cell_type       = "code",
      id              = paste0("cell_", i),
      metadata        = list(),
      source          = list(paste0("x", i, " = ", i)),
      outputs         = list(),
      execution_count = NULL
    )
  })
  nb <- list(
    nbformat       = 4L,
    nbformat_minor = 5L,
    metadata       = list(kernelspec = list(name = "ir")),
    cells          = cells
  )
  writeLines(
    jsonlite::toJSON(nb, auto_unbox = TRUE, pretty = TRUE, null = "null"),
    path
  )
  invisible(path)
}

# ---------------------------------------------------------------------------
# NotebookRead: basic sanity
# ---------------------------------------------------------------------------

test_that("notebook_read_tool: returns error for missing file", {
  tool   <- codeagent:::notebook_read_tool()
  result <- tool("/nonexistent/path.ipynb")
  expect_match(result, "\\[Error\\].*not found", ignore.case = TRUE)
})

test_that("notebook_read_tool: returns cell content from valid notebook", {
  tmp <- withr::local_tempfile(fileext = ".ipynb")
  .make_ipynb(tmp, n_cells = 2L)
  tool   <- codeagent:::notebook_read_tool()
  result <- tool(tmp)
  expect_true(is.character(result))
  expect_match(result, "Cell 0", fixed = TRUE)
  expect_match(result, "Cell 1", fixed = TRUE)
})

# ---------------------------------------------------------------------------
# NotebookEdit: insert mode — edge cases
# ---------------------------------------------------------------------------

test_that("notebook_edit_tool: insert appends when no cell_number given", {
  tmp <- withr::local_tempfile(fileext = ".ipynb")
  .make_ipynb(tmp, n_cells = 2L)
  tool <- codeagent:::notebook_edit_tool(mode = "bypass")
  result <- tool(tmp, "new_cell = 99", cell_number = NULL, edit_mode = "insert")
  expect_match(result, "NotebookEdit applied")

  nb    <- jsonlite::fromJSON(tmp, simplifyVector = FALSE)
  cells <- nb[["cells"]]
  expect_equal(length(cells), 3L)  # original 2 + 1 inserted
  src <- paste(unlist(cells[[3L]][["source"]]), collapse = "")
  expect_match(src, "new_cell")
})

test_that("notebook_edit_tool: insert after last cell appends (not corrupted)", {
  # Bug: cells[(idx+1):length(cells)] when idx==length(cells) was reversed.
  tmp <- withr::local_tempfile(fileext = ".ipynb")
  .make_ipynb(tmp, n_cells = 3L)
  tool <- codeagent:::notebook_edit_tool(mode = "bypass")

  # cell_number=2 (0-indexed) = idx=3 (1-indexed) = last cell
  result <- tool(tmp, "appended = True", cell_number = 2, edit_mode = "insert")
  expect_match(result, "NotebookEdit applied")

  nb    <- jsonlite::fromJSON(tmp, simplifyVector = FALSE)
  cells <- nb[["cells"]]
  # Should now have 4 cells, not 3 original + corrupted duplicates
  expect_equal(length(cells), 4L)
  # New cell should be the 4th (last)
  src_last <- paste(unlist(cells[[4L]][["source"]]), collapse = "")
  expect_match(src_last, "appended")
  # Original cells 1-3 should be unchanged (check cell 3)
  src_third <- paste(unlist(cells[[3L]][["source"]]), collapse = "")
  expect_match(src_third, "x3")
})

test_that("notebook_edit_tool: insert in the middle inserts correctly", {
  tmp <- withr::local_tempfile(fileext = ".ipynb")
  .make_ipynb(tmp, n_cells = 3L)
  tool <- codeagent:::notebook_edit_tool(mode = "bypass")

  # Insert after cell_number=1 (0-indexed) = after 2nd cell
  result <- tool(tmp, "middle = True", cell_number = 1, edit_mode = "insert")
  expect_match(result, "NotebookEdit applied")

  nb    <- jsonlite::fromJSON(tmp, simplifyVector = FALSE)
  cells <- nb[["cells"]]
  expect_equal(length(cells), 4L)

  src_new <- paste(unlist(cells[[3L]][["source"]]), collapse = "")
  expect_match(src_new, "middle")
  # Cell originally at index 3 (source "x3") should now be at index 4
  src_pushed <- paste(unlist(cells[[4L]][["source"]]), collapse = "")
  expect_match(src_pushed, "x3")
})

# ---------------------------------------------------------------------------
# NotebookEdit: replace and delete modes
# ---------------------------------------------------------------------------

test_that("notebook_edit_tool: replace mode updates cell source", {
  tmp <- withr::local_tempfile(fileext = ".ipynb")
  .make_ipynb(tmp, n_cells = 3L)
  tool <- codeagent:::notebook_edit_tool(mode = "bypass")
  result <- tool(tmp, "replaced = True", cell_number = 0, edit_mode = "replace")
  expect_match(result, "NotebookEdit applied")

  nb  <- jsonlite::fromJSON(tmp, simplifyVector = FALSE)
  src <- paste(unlist(nb[["cells"]][[1L]][["source"]]), collapse = "")
  expect_match(src, "replaced")
})

test_that("notebook_edit_tool: replace requires cell_number or cell_id", {
  tmp <- withr::local_tempfile(fileext = ".ipynb")
  .make_ipynb(tmp, n_cells = 2L)
  tool   <- codeagent:::notebook_edit_tool(mode = "bypass")
  result <- tool(tmp, "x = 1", cell_number = NULL, cell_id = NULL,
                 edit_mode = "replace")
  expect_match(result, "\\[Error\\].*required", ignore.case = TRUE)
})

test_that("notebook_edit_tool: delete mode removes the cell", {
  tmp <- withr::local_tempfile(fileext = ".ipynb")
  .make_ipynb(tmp, n_cells = 3L)
  tool   <- codeagent:::notebook_edit_tool(mode = "bypass")
  result <- tool(tmp, "", cell_number = 1, edit_mode = "delete")
  expect_match(result, "NotebookEdit applied")

  nb <- jsonlite::fromJSON(tmp, simplifyVector = FALSE)
  expect_equal(length(nb[["cells"]]), 2L)
})
