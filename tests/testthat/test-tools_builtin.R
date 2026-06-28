# tests/testthat/test-tools_builtin.R
# Unit tests for built-in tool logic (no API calls needed).
#
# ellmer::tool() returns an S7 ToolDef that extends `function`, so tools
# are directly callable: tool_obj(arg1, arg2, ...).

# ---------------------------------------------------------------------------
# read_tool: limit=0 / offset-past-EOF bugs
# ---------------------------------------------------------------------------

test_that("read_tool: limit=0 returns empty string", {
  tmp <- withr::local_tempfile()
  writeLines(c("line1", "line2", "line3"), tmp)
  tool <- codeagent:::read_tool()
  expect_equal(tool(tmp, offset = NULL, limit = 0), "")
})

test_that("read_tool: offset past EOF returns empty string", {
  tmp <- withr::local_tempfile()
  writeLines(c("line1", "line2"), tmp)
  tool <- codeagent:::read_tool()
  expect_equal(tool(tmp, offset = 99, limit = NULL), "")
})

test_that("read_tool: offset=2 limit=1 returns exactly line 2", {
  tmp <- withr::local_tempfile()
  writeLines(c("alpha", "beta", "gamma"), tmp)
  tool <- codeagent:::read_tool()
  result <- tool(tmp, offset = 2, limit = 1)
  expect_match(result, "^2\tbeta$")
  expect_false(grepl("alpha", result))
  expect_false(grepl("gamma", result))
})

test_that("read_tool: line numbers are in ascending order (not reversed)", {
  tmp <- withr::local_tempfile()
  writeLines(c("A", "B", "C", "D", "E"), tmp)
  tool <- codeagent:::read_tool()
  result <- tool(tmp, offset = 2, limit = 3)
  nums   <- as.integer(sub("\t.*", "", strsplit(result, "\n")[[1L]]))
  expect_equal(nums, c(2L, 3L, 4L))
})

# ---------------------------------------------------------------------------
# edit_tool: gregexpr no-match detection
# ---------------------------------------------------------------------------

test_that("edit_tool returns error when old_string not found", {
  tmp <- withr::local_tempfile()
  writeLines(c("hello world", "foo bar"), tmp)
  tool   <- codeagent:::edit_tool(mode = "bypass")
  result <- tool(tmp, "NONEXISTENT_STRING", "replacement", replace_all = FALSE)
  expect_match(result, "\\[Error\\].*not found", ignore.case = TRUE)
  expect_equal(readLines(tmp), c("hello world", "foo bar"))
})

test_that("edit_tool returns error when old_string appears more than once", {
  tmp <- withr::local_tempfile()
  writeLines(c("dup line", "dup line", "other"), tmp)
  tool   <- codeagent:::edit_tool(mode = "bypass")
  result <- tool(tmp, "dup line", "replaced", replace_all = FALSE)
  expect_match(result, "\\[Error\\].*2.*times", ignore.case = TRUE)
})

test_that("edit_tool succeeds when old_string appears exactly once", {
  tmp <- withr::local_tempfile()
  writeLines(c("find me", "leave alone"), tmp)
  tool   <- codeagent:::edit_tool(mode = "bypass")
  result <- tool(tmp, "find me", "replaced", replace_all = FALSE)
  expect_match(result, "Edited:")
  content <- paste(readLines(tmp), collapse = "\n")
  expect_true(grepl("replaced", content))
  expect_false(grepl("find me", content))
})

# ---------------------------------------------------------------------------
# multi_edit_tool: gregexpr no-match detection
# ---------------------------------------------------------------------------

test_that("multi_edit_tool returns error when old_string not found", {
  tmp <- withr::local_tempfile()
  writeLines(c("existing content", "second line"), tmp)
  tool   <- codeagent:::multi_edit_tool(mode = "bypass")
  edits  <- list(list(old_string = "DOES_NOT_EXIST", new_string = "X"))
  result <- tool(tmp, edits)
  expect_match(result, "\\[Error\\].*found 0", ignore.case = TRUE)
  expect_equal(readLines(tmp), c("existing content", "second line"))
})

test_that("multi_edit_tool aborts on first failed edit without partial apply", {
  tmp <- withr::local_tempfile()
  writeLines(c("aaa", "bbb"), tmp)
  tool  <- codeagent:::multi_edit_tool(mode = "bypass")
  edits <- list(list(old_string = "MISSING", new_string = "X"))
  result <- tool(tmp, edits)
  expect_match(result, "\\[Error\\]", ignore.case = TRUE)
  expect_equal(readLines(tmp), c("aaa", "bbb"))
})

# ---------------------------------------------------------------------------
# bash_tool: run_in_background
# ---------------------------------------------------------------------------

test_that("bash_tool: run_in_background=TRUE returns background message immediately", {
  tool   <- codeagent:::bash_tool(mode = "bypass")
  # Use a harmless no-op command; timing would be flaky so just check return value.
  result <- tool("true", run_in_background = TRUE)
  expect_match(result, "Background", ignore.case = TRUE)
  expect_match(result, "command started", ignore.case = TRUE)
})

test_that("bash_tool: run_in_background=FALSE (default) does NOT return background message", {
  tool   <- codeagent:::bash_tool(mode = "bypass")
  # Verify the normal (synchronous) code path is taken: no "Background" in result.
  result <- tool("true")
  expect_false(grepl("Background", result, ignore.case = TRUE))
})

# ---------------------------------------------------------------------------
# glob_tool: ** pattern portability (.glob_with_starstar)
# ---------------------------------------------------------------------------

test_that(".glob_with_starstar: **/*.R finds R files recursively", {
  # Create a temporary directory tree with R files at multiple depths.
  tmpdir <- withr::local_tempdir()
  dir.create(file.path(tmpdir, "sub"), showWarnings = FALSE)
  writeLines("x <- 1", file.path(tmpdir, "top.R"))
  writeLines("y <- 2", file.path(tmpdir, "sub", "nested.R"))
  writeLines("not_r",  file.path(tmpdir, "sub", "file.txt"))

  found <- codeagent:::.glob_with_starstar(tmpdir, "**/*.R")
  basenames <- sort(basename(found))
  expect_true("top.R" %in% basenames)
  expect_true("nested.R" %in% basenames)
  expect_false("file.txt" %in% basenames)
})

test_that(".glob_with_starstar: prefix/**/*.R restricts to subdirectory", {
  tmpdir <- withr::local_tempdir()
  dir.create(file.path(tmpdir, "src", "sub"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(tmpdir, "other"),      showWarnings = FALSE)
  writeLines("1", file.path(tmpdir, "src", "a.R"))
  writeLines("2", file.path(tmpdir, "src", "sub", "b.R"))
  writeLines("3", file.path(tmpdir, "other", "c.R"))

  found <- codeagent:::.glob_with_starstar(tmpdir, "src/**/*.R")
  basenames <- basename(found)
  expect_true("a.R" %in% basenames)
  expect_true("b.R" %in% basenames)
  expect_false("c.R" %in% basenames)  # outside src/
})

test_that("glob_tool: **/*.R pattern returns R files via portable helper", {
  tmpdir <- withr::local_tempdir()
  dir.create(file.path(tmpdir, "deep", "dir"), recursive = TRUE, showWarnings = FALSE)
  writeLines("a <- 1", file.path(tmpdir, "root.R"))
  writeLines("b <- 2", file.path(tmpdir, "deep", "dir", "leaf.R"))

  tool   <- codeagent:::glob_tool()
  result <- tool("**/*.R", path = tmpdir)

  expect_false(identical(result, "No files matched."))
  expect_match(result, "root\\.R")
  expect_match(result, "leaf\\.R")
})

test_that("glob_tool: non-** pattern still works via Sys.glob", {
  tmpdir <- withr::local_tempdir()
  writeLines("x <- 1", file.path(tmpdir, "script.R"))
  writeLines("ignored", file.path(tmpdir, "script.txt"))

  tool   <- codeagent:::glob_tool()
  result <- tool("*.R", path = tmpdir)
  expect_match(result, "script\\.R")
  expect_false(grepl("script\\.txt", result))
})

# ---------------------------------------------------------------------------
# grep_tool: R fallback separator bug (rg absent)
# ---------------------------------------------------------------------------

test_that("grep_tool fallback: -n=TRUE produces filepath:linenum:content", {
  # When rg is absent the R fallback must produce "file:N:content" format.
  tmpdir <- withr::local_tempdir()
  writeLines(c("hello world", "foo bar", "hello again"),
             file.path(tmpdir, "test.R"))

  tool   <- codeagent:::grep_tool()
  result <- tool("hello", path = tmpdir, glob = "*.R", `-n` = TRUE)

  # Each match line must contain at least two colons (path:num:content).
  lines <- strsplit(result, "\n")[[1L]]
  match_lines <- grep("hello", lines, value = TRUE)
  expect_true(length(match_lines) >= 1L)
  # Pattern: <path>:<digit(s)>:<content> — at minimum two colons
  for (ml in match_lines) {
    expect_true(lengths(regmatches(ml, gregexpr(":", ml, fixed = TRUE))) >= 2L,
                info = paste("line missing colon separators:", ml))
  }
})

test_that("grep_tool fallback: -n=FALSE produces filepath:content (colon present)", {
  # Regression for bug where 'else f' (no colon) caused "filepath content"
  # to be concatenated without any separator, e.g. "/tmp/fileXXX.Rhello world".
  tmpdir <- withr::local_tempdir()
  writeLines(c("hello world", "foo bar", "hello again"),
             file.path(tmpdir, "sample.R"))

  tool   <- codeagent:::grep_tool()
  result <- tool("hello", path = tmpdir, glob = "*.R", `-n` = FALSE)

  # Must NOT produce <extension><letter> with no colon in between (old bug).
  # e.g. ".Rhello" would indicate missing separator.
  expect_false(grepl("\\.R[^:\n/]", result),
               info = paste("missing colon separator in result:", result))

  # Must produce filepath:content format.
  expect_match(result, "\\.R:hello")
})

test_that("grep_tool fallback: files_with_matches mode returns unique paths", {
  tmpdir <- withr::local_tempdir()
  writeLines(c("needle here", "another needle", "no match"),
             file.path(tmpdir, "haystack.R"))

  tool   <- codeagent:::grep_tool()
  result <- tool("needle", path = tmpdir, glob = "*.R",
                 output_mode = "files_with_matches")

  lines <- strsplit(result, "\n")[[1L]]
  # Only one unique file path should appear (deduplication).
  expect_equal(length(lines), 1L)
  expect_match(lines[[1L]], "haystack\\.R")
})

test_that("grep_tool fallback: count mode returns filepath:N", {
  tmpdir <- withr::local_tempdir()
  writeLines(c("needle here", "another needle", "no match"),
             file.path(tmpdir, "haystack.R"))

  tool   <- codeagent:::grep_tool()
  result <- tool("needle", path = tmpdir, glob = "*.R",
                 output_mode = "count")

  expect_match(result, "haystack\\.R:2")
})
