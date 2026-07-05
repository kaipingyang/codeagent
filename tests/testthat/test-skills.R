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

test_that(".preprocess_input: local command returns type='command'", {
  r <- codeagent:::.preprocess_input("/compact some args")
  expect_equal(r$type, "command")  # compact is a local command
  expect_equal(r$name, "compact")
  expect_equal(r$args, "some args")
})

test_that(".preprocess_input detects skill in clean input", {
  r <- codeagent:::.preprocess_input("/plan refactor utils")
  expect_equal(r$type, "skill")    # plan is a skill (sent to LLM)
  expect_equal(r$name, "plan")
  expect_equal(r$args, "refactor utils")
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
  expect_equal(r$type, "command")  # compact is a local command
  expect_equal(r$name, "compact")
  expect_equal(r$args, "")
})

test_that(".preprocess_input: all local commands return type='command'", {
  for (cmd in c("model", "compact", "clear", "rewind")) {
    r <- codeagent:::.preprocess_input(paste0("/", cmd))
    expect_equal(r$type, "command", info = paste("command:", cmd))
    expect_equal(r$name, cmd, info = paste("name:", cmd))
  }
})

test_that(".preprocess_input: unknown slash word returns type='skill'", {
  r <- codeagent:::.preprocess_input("/plan refactor this")
  expect_equal(r$type, "skill")
  r2 <- codeagent:::.preprocess_input("/verify")
  expect_equal(r2$type, "skill")
})

# ---------------------------------------------------------------------------
# Regression: input normalization for shinychat dev allow_attachments=TRUE.
# input$chat_user_input is a contents LIST (e.g. list("hello")), not a string.
# The old code ran it through shinychat:::user_input_contents() which returns
# an EMPTY list() for this format -> as.character(list()) == character(0) ->
# .preprocess_input crashed with "subscript out of bounds" and the message was
# silently dropped (no LLM call). See inst/experiments/capture_input/ evidence.
# ---------------------------------------------------------------------------

test_that(".preprocess_input never crashes on degenerate input", {
  # These previously threw "subscript out of bounds" via regmatches()[[1L]].
  expect_equal(codeagent:::.preprocess_input(character(0))$type, "normal")
  expect_equal(codeagent:::.preprocess_input(NULL)$type, "normal")
  expect_equal(codeagent:::.preprocess_input(list())$type, "normal")
  expect_equal(codeagent:::.preprocess_input("")$type, "normal")
})

test_that(".user_input_text extracts text from all shinychat input shapes", {
  # allow_attachments = TRUE, plain text typed -> contents list of one string
  expect_equal(codeagent:::.user_input_text(list("hello world")), "hello world")
  # allow_attachments = TRUE, slash skill
  expect_equal(codeagent:::.user_input_text(list("/plan refactor")), "/plan refactor")
  # allow_attachments = FALSE -> plain character scalar
  expect_equal(codeagent:::.user_input_text("hello world"), "hello world")
  # legacy {text, attachments} wire payload
  expect_equal(codeagent:::.user_input_text(list(text = "wire", attachments = NULL)), "wire")
  # degenerate -> "" (never errors)
  expect_equal(codeagent:::.user_input_text(list()), "")
  expect_equal(codeagent:::.user_input_text(NULL), "")
})

test_that("contents-list input round-trips to a slash decision (the crash path)", {
  # The exact captured value that used to crash: list("你好") from Microsoft
  # Pinyin / any text with allow_attachments = TRUE.
  tp <- codeagent:::.user_input_text(list("\u4f60\u597d"))
  expect_equal(tp, "\u4f60\u597d")
  expect_equal(codeagent:::.preprocess_input(tp)$type, "normal")
})
