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
  expect_equal(meta$argument_hint, "<task>")   # surrounding quotes stripped
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

test_that("list_skills_meta reads the on-disk cache in a fresh process", {
  home <- withr::local_tempdir()
  withr::local_envvar(CODEAGENT_HOME = home)
  withr::local_options(codeagent._migrated = TRUE)  # skip config migration
  tmp_dir    <- withr::local_tempdir()
  skills_dir <- file.path(tmp_dir, ".btw", "skills", "myskill")
  dir.create(skills_dir, recursive = TRUE, showWarnings = FALSE)
  writeLines(c("---", "name: myskill", "description: disk", "---", "body"),
             file.path(skills_dir, "SKILL.md"))

  # First call: full scan + persists to disk.
  metas1 <- codeagent:::list_skills_meta(cwd = tmp_dir)
  expect_true("myskill" %in% names(metas1))
  cache_key <- codeagent:::.sanitize_path(codeagent:::.canonicalize_path(tmp_dir))
  expect_true(file.exists(codeagent:::.skill_cache_file(cache_key)))

  # Simulate a fresh process: drop the in-memory cache, then overwrite the disk
  # copy with a sentinel at the SAME signature. A disk HIT must return it
  # (a rescan would not know about SENTINEL).
  rm(list = cache_key, envir = codeagent:::.skill_cache)
  sig <- codeagent:::.skill_dirs_mtime_sig(codeagent:::.skill_dirs(tmp_dir))
  sentinel <- list(SENTINEL = codeagent:::SkillMeta(name = "SENTINEL", description = "x"))
  codeagent:::.skill_cache_write(cache_key, sig, sentinel)

  metas2 <- codeagent:::list_skills_meta(cwd = tmp_dir)
  expect_true("SENTINEL" %in% names(metas2))
})

test_that("on-disk skill cache invalidates when a SKILL.md changes", {
  home <- withr::local_tempdir()
  withr::local_envvar(CODEAGENT_HOME = home)
  withr::local_options(codeagent._migrated = TRUE)
  tmp_dir    <- withr::local_tempdir()
  skills_dir <- file.path(tmp_dir, ".btw", "skills", "myskill")
  dir.create(skills_dir, recursive = TRUE, showWarnings = FALSE)
  skill_path <- file.path(skills_dir, "SKILL.md")
  writeLines(c("---", "name: myskill", "description: v1", "---", "body"), skill_path)

  metas1 <- codeagent:::list_skills_meta(cwd = tmp_dir)
  expect_equal(metas1[["myskill"]]$description, "v1")

  # Fresh process (drop in-memory) + changed file -> stale disk sig -> rescan.
  cache_key <- codeagent:::.sanitize_path(codeagent:::.canonicalize_path(tmp_dir))
  rm(list = cache_key, envir = codeagent:::.skill_cache)
  Sys.sleep(0.1)
  writeLines(c("---", "name: myskill", "description: v2", "---", "body"), skill_path)
  metas2 <- codeagent:::list_skills_meta(cwd = tmp_dir)
  expect_equal(metas2[["myskill"]]$description, "v2")
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


test_that(".parse_skill_md reads argument-hint from metadata (btw-compatible) + legacy top-level", {
  dir <- withr::local_tempdir()

  # New spec-compliant form: argument-hint nested under `metadata:`.
  d1 <- file.path(dir, "newform"); dir.create(d1)
  writeLines(c("---", "name: newform", "description: d",
               "metadata:", "  argument-hint: \"<x> <y>\"",
               "allowed-tools:", "  - RunR", "---", "body"),
             file.path(d1, "SKILL.md"))
  m1 <- codeagent:::.parse_skill_md(file.path(d1, "SKILL.md"))
  expect_identical(m1$argument_hint, "<x> <y>")   # read from metadata, quotes stripped

  # Legacy top-level argument-hint still works.
  d2 <- file.path(dir, "oldform"); dir.create(d2)
  writeLines(c("---", "name: oldform", "description: d",
               "argument-hint: \"<z>\"", "---", "body"),
             file.path(d2, "SKILL.md"))
  m2 <- codeagent:::.parse_skill_md(file.path(d2, "SKILL.md"))
  expect_identical(m2$argument_hint, "<z>")

  # Empty / absent hint -> "".
  d3 <- file.path(dir, "nohint"); dir.create(d3)
  writeLines(c("---", "name: nohint", "description: d", "---", "body"),
             file.path(d3, "SKILL.md"))
  m3 <- codeagent:::.parse_skill_md(file.path(d3, "SKILL.md"))
  expect_identical(m3$argument_hint, "")
})

# ---------------------------------------------------------------------------
# Package-provided skills that are not attached (Plan 38)
# ---------------------------------------------------------------------------

test_that("explicit package skills are discovered without attaching the package", {
  shiny_skills <- withr::local_tempdir()
  dir.create(file.path(shiny_skills, "shiny-for-r"), recursive = TRUE)
  writeLines(c(
    "---", "name: shiny-for-r", "description: Shiny skill", "---", "body"),
    file.path(shiny_skills, "shiny-for-r", "SKILL.md"))

  testthat::local_mocked_bindings(
    .package_skill_path = function(package) {
      if (identical(package, "shiny")) shiny_skills else ""
    }
  )

  expect_identical(codeagent:::.package_skill_dirs("shiny"), shiny_skills)
})

test_that(".skill_dirs adds the explicit Shiny skill directory once", {
  shiny_skills <- withr::local_tempdir()
  testthat::local_mocked_bindings(
    .package_skill_dirs = function(packages) c(shiny_skills, shiny_skills)
  )

  dirs <- codeagent:::.skill_dirs(withr::local_tempdir())
  expect_identical(sum(dirs == shiny_skills), 1L)
})


test_that("Shiny built-in skill is listed without attaching shiny", {
  shiny_skills <- system.file("skills", package = "shiny")
  skip_if(!nzchar(shiny_skills) || !dir.exists(shiny_skills))
  was_attached <- "package:shiny" %in% search()
  if (was_attached) {
    detach("package:shiny", unload = FALSE, character.only = TRUE)
    withr::defer(suppressPackageStartupMessages(
      library("shiny", character.only = TRUE)))
  }
  expect_false("package:shiny" %in% search())

  metas <- list_skills_meta(withr::local_tempdir())
  expect_true("shiny-for-r" %in% names(metas))
  expect_match(metas[["shiny-for-r"]]$path, "shiny-for-r/SKILL.md", fixed = TRUE)
})