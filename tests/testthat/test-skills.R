test_that(".parse_skill_frontmatter returns NULL for files without ---", {
  tmp <- withr::local_tempfile(fileext = ".md")
  writeLines(c("# No frontmatter", "Just content."), tmp)
  expect_null(codeagent:::.parse_skill_frontmatter(tmp))
})

test_that(".parse_skill_frontmatter returns NULL for non-existent file", {
  expect_null(codeagent:::.parse_skill_frontmatter("/nonexistent/skill.md"))
})

test_that(".parse_skill_frontmatter parses name, description, context", {
  tmp <- withr::local_tempfile(fileext = ".md")
  writeLines(c(
    "---",
    "name: my-skill",
    "description: A test skill",
    "context: inline",
    "---",
    "This is the skill body."
  ), tmp)
  meta <- codeagent:::.parse_skill_frontmatter(tmp)
  expect_false(is.null(meta))
  expect_equal(meta$name,        "my-skill")
  expect_equal(meta$description, "A test skill")
  expect_equal(meta$context,     "inline")
})

test_that(".parse_skill_frontmatter falls back to filename if name missing", {
  tmp <- withr::local_tempfile(fileext = ".md")
  writeLines(c("---", "description: No name field", "---", "Body."), tmp)
  meta <- codeagent:::.parse_skill_frontmatter(tmp)
  expect_false(is.null(meta))
  # Name should be filename stem
  expect_true(nzchar(meta$name))
  expect_false(identical(meta$name, ""))
})

test_that(".substitute_args replaces $ARGUMENTS and $ARG1/$ARG2", {
  body <- "Run with args: $ARGUMENTS. First: $ARG1. Second: $ARG2."
  result <- codeagent:::.substitute_args(body, "foo bar")
  expect_equal(result, "Run with args: foo bar. First: foo. Second: bar.")
})

test_that(".substitute_args leaves unmatched $ARGn untouched", {
  body <- "Only one arg: $ARG1. Missing: $ARG2."
  result <- codeagent:::.substitute_args(body, "hello")
  expect_equal(result, "Only one arg: hello. Missing: $ARG2.")
})

test_that("list_skills_meta caches results and invalidates on file change", {
  tmp_dir    <- withr::local_tempdir()
  skills_dir <- file.path(tmp_dir, ".codeagent", "skills")
  dir.create(skills_dir, recursive = TRUE, showWarnings = FALSE)

  skill_path <- file.path(skills_dir, "myskill.md")
  writeLines(c("---", "name: myskill", "description: desc", "---", "body"), skill_path)

  metas1 <- codeagent:::list_skills_meta(cwd = tmp_dir)
  metas2 <- codeagent:::list_skills_meta(cwd = tmp_dir)
  # Second call should use cache (identical objects)
  expect_identical(metas1, metas2)
  expect_true("myskill" %in% names(metas1))

  # After modifying the file, cache should be invalidated
  Sys.sleep(0.1)
  writeLines(c("---", "name: myskill", "description: updated", "---", "body"), skill_path)
  metas3 <- codeagent:::list_skills_meta(cwd = tmp_dir)
  expect_equal(metas3[["myskill"]]$description, "updated")
})

test_that(".strip_frontmatter removes YAML front matter", {
  lines <- c("---", "name: test", "---", "# Heading", "Body content")
  result <- codeagent:::.strip_frontmatter(lines)
  expect_equal(result, c("# Heading", "Body content"))
})

test_that(".strip_frontmatter returns lines unchanged if no front matter", {
  lines <- c("# Heading", "Body content")
  result <- codeagent:::.strip_frontmatter(lines)
  expect_equal(result, lines)
})

# ---------------------------------------------------------------------------
# .preprocess_input: regmatches must use same string as regexec
# ---------------------------------------------------------------------------

test_that(".preprocess_input detects skill in clean input", {
  r <- codeagent:::.preprocess_input("/compact some args")
  expect_equal(r$type, "skill")
  expect_equal(r$name, "compact")
  expect_equal(r$args, "some args")
})

test_that(".preprocess_input handles leading/trailing whitespace correctly", {
  # Bug: regexec was on trimws(input) but regmatches on untrimmed input
  r <- codeagent:::.preprocess_input("  /plan refactor utils  ")
  expect_equal(r$type, "skill")
  expect_equal(r$name, "plan")
  expect_equal(r$args, "refactor utils")
})

test_that(".preprocess_input: whitespace-only input returns normal", {
  r <- codeagent:::.preprocess_input("   ")
  expect_equal(r$type, "normal")
})

test_that(".preprocess_input: non-skill input returns normal type", {
  r <- codeagent:::.preprocess_input("just a regular message")
  expect_equal(r$type, "normal")
  expect_equal(r$input, "just a regular message")
})

test_that(".preprocess_input: /skill with no args has empty args string", {
  r <- codeagent:::.preprocess_input("/compact")
  expect_equal(r$type, "skill")
  expect_equal(r$name, "compact")
  expect_equal(r$args, "")
})
