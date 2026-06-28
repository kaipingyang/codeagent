# tests/testthat/test-skills.R
# Updated for btw-compatible skill system (name/SKILL.md directory format)

# ---------------------------------------------------------------------------
# .parse_skill_md: new SKILL.md parser
# ---------------------------------------------------------------------------

test_that(".parse_skill_md returns NULL for files without ---", {
  tmp_dir <- withr::local_tempdir()
  skill_md <- file.path(tmp_dir, "SKILL.md")
  writeLines(c("# No frontmatter", "Just content."), skill_md)
  expect_null(codeagent:::.parse_skill_md(skill_md))
})

test_that(".parse_skill_md returns NULL for non-existent file", {
  expect_null(codeagent:::.parse_skill_md("/nonexistent/SKILL.md"))
})

test_that(".parse_skill_md parses name, description, argument-hint", {
  tmp_dir  <- withr::local_tempdir()
  skill_md <- file.path(tmp_dir, "SKILL.md")
  writeLines(c(
    "---",
    "name: my-skill",
    "description: A test skill",
    "argument-hint: \"<task>\"",
    "---",
    "This is the skill body."
  ), skill_md)
  meta <- codeagent:::.parse_skill_md(skill_md)
  expect_false(is.null(meta))
  expect_equal(meta$name,          "my-skill")
  expect_equal(meta$description,   "A test skill")
  expect_equal(meta$argument_hint, '"<task>"')
})

test_that(".parse_skill_md auto_trigger defaults to TRUE", {
  tmp_dir  <- withr::local_tempdir()
  skill_md <- file.path(tmp_dir, "SKILL.md")
  writeLines(c("---", "name: s", "description: d", "---", "body"), skill_md)
  meta <- codeagent:::.parse_skill_md(skill_md)
  expect_true(meta$auto_trigger)
})

test_that(".parse_skill_md auto_trigger can be disabled", {
  tmp_dir  <- withr::local_tempdir()
  skill_md <- file.path(tmp_dir, "SKILL.md")
  writeLines(c("---", "name: s", "description: d", "auto-trigger: false", "---", "body"),
             skill_md)
  meta <- codeagent:::.parse_skill_md(skill_md)
  expect_false(meta$auto_trigger)
})

test_that(".parse_skill_md falls back to directory name if name missing", {
  tmp_dir  <- withr::local_tempdir()
  skill_md <- file.path(tmp_dir, "SKILL.md")
  writeLines(c("---", "description: No name field", "---", "Body."), skill_md)
  meta <- codeagent:::.parse_skill_md(skill_md)
  expect_false(is.null(meta))
  expect_true(nzchar(meta$name))
})

# ---------------------------------------------------------------------------
# list_skills_meta: discovers SKILL.md directories
# ---------------------------------------------------------------------------

test_that("list_skills_meta discovers SKILL.md directories in .btw/skills", {
  tmp_dir    <- withr::local_tempdir()
  skills_dir <- file.path(tmp_dir, ".btw", "skills", "myskill")
  dir.create(skills_dir, recursive = TRUE, showWarnings = FALSE)
  writeLines(c("---", "name: myskill", "description: desc", "---", "body"),
             file.path(skills_dir, "SKILL.md"))

  metas <- codeagent:::list_skills_meta(cwd = tmp_dir)
  expect_true("myskill" %in% names(metas))
  expect_equal(metas[["myskill"]]$description, "desc")
})

test_that("list_skills_meta caches and invalidates on SKILL.md change", {
  tmp_dir    <- withr::local_tempdir()
  skills_dir <- file.path(tmp_dir, ".btw", "skills", "myskill")
  dir.create(skills_dir, recursive = TRUE, showWarnings = FALSE)
  skill_path <- file.path(skills_dir, "SKILL.md")
  writeLines(c("---", "name: myskill", "description: v1", "---", "body"), skill_path)

  metas1 <- codeagent:::list_skills_meta(cwd = tmp_dir)
  metas2 <- codeagent:::list_skills_meta(cwd = tmp_dir)
  expect_identical(metas1, metas2)

  Sys.sleep(0.1)
  writeLines(c("---", "name: myskill", "description: v2", "---", "body"), skill_path)
  metas3 <- codeagent:::list_skills_meta(cwd = tmp_dir)
  expect_equal(metas3[["myskill"]]$description, "v2")
})

test_that("list_skills_meta discovers .claude/skills/ directory", {
  tmp_dir    <- withr::local_tempdir()
  skills_dir <- file.path(tmp_dir, ".claude", "skills", "claude-skill")
  dir.create(skills_dir, recursive = TRUE, showWarnings = FALSE)
  writeLines(c("---", "name: claude-skill", "description: from claude", "---", "body"),
             file.path(skills_dir, "SKILL.md"))

  metas <- codeagent:::list_skills_meta(cwd = tmp_dir)
  expect_true("claude-skill" %in% names(metas))
})

test_that("list_skills_meta discovers .codex/skills/ directory", {
  tmp_dir    <- withr::local_tempdir()
  skills_dir <- file.path(tmp_dir, ".codex", "skills", "codex-skill")
  dir.create(skills_dir, recursive = TRUE, showWarnings = FALSE)
  writeLines(c("---", "name: codex-skill", "description: from codex", "---", "body"),
             file.path(skills_dir, "SKILL.md"))

  metas <- codeagent:::list_skills_meta(cwd = tmp_dir)
  expect_true("codex-skill" %in% names(metas))
})

# ---------------------------------------------------------------------------
# .substitute_args
# ---------------------------------------------------------------------------

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

# ---------------------------------------------------------------------------
# .strip_frontmatter
# ---------------------------------------------------------------------------

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
# .preprocess_input
# ---------------------------------------------------------------------------

test_that(".preprocess_input detects skill in clean input", {
  r <- codeagent:::.preprocess_input("/compact some args")
  expect_equal(r$type, "skill")
  expect_equal(r$name, "compact")
  expect_equal(r$args, "some args")
})

test_that(".preprocess_input handles leading/trailing whitespace correctly", {
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
