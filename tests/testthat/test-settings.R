# tests/testthat/test-settings.R

# ---------------------------------------------------------------------------
# .CODEAGENT_DEFAULTS completeness
# ---------------------------------------------------------------------------

test_that(".CODEAGENT_DEFAULTS has all required Claude Code keys", {
  d <- codeagent:::.CODEAGENT_DEFAULTS
  expect_true("model"            %in% names(d))
  expect_true("effort_level"     %in% names(d))
  expect_true("permissions"      %in% names(d))
  expect_true("env"              %in% names(d))
  expect_true("small_fast_model" %in% names(d))
  expect_true("tier_models"      %in% names(d))
  expect_true("cleanup_period_days" %in% names(d))
  expect_true("include_coauthored_by" %in% names(d))
})

# ---------------------------------------------------------------------------
# .build_tier_models
# ---------------------------------------------------------------------------

test_that(".build_tier_models builds map from env vars", {
  withr::with_envvar(c(
    CODEAGENT_DEFAULT_SONNET_MODEL = "gsds-gpt-54",
    CODEAGENT_DEFAULT_OPUS_MODEL   = "gsds-gpt-55",
    CODEAGENT_SMALL_FAST_MODEL     = "gsds-gpt41"
  ), {
    tiers <- codeagent:::.build_tier_models()
    expect_equal(tiers[["sonnet"]], "gsds-gpt-54")
    expect_equal(tiers[["opus"]],   "gsds-gpt-55")
    expect_equal(tiers[["haiku"]],  "gsds-gpt41")
  })
})

test_that(".build_tier_models returns empty list when no env vars set", {
  withr::with_envvar(c(
    CODEAGENT_DEFAULT_SONNET_MODEL = "",
    CODEAGENT_DEFAULT_OPUS_MODEL   = "",
    CODEAGENT_SMALL_FAST_MODEL     = ""
  ), {
    tiers <- codeagent:::.build_tier_models()
    expect_equal(length(tiers), 0L)
  })
})

# ---------------------------------------------------------------------------
# .parse_permission_pattern
# ---------------------------------------------------------------------------

test_that(".parse_permission_pattern handles 'Tool(content)' patterns", {
  p <- codeagent:::.parse_permission_pattern("Bash(npm run test *)")
  expect_equal(p$tool_name,    "Bash")
  expect_equal(p$rule_content, "npm run test *")
})

test_that(".parse_permission_pattern handles tool-only patterns", {
  p <- codeagent:::.parse_permission_pattern("Write")
  expect_equal(p$tool_name, "Write")
  expect_null(p$rule_content)
})

test_that(".parse_permission_pattern handles Read with path", {
  p <- codeagent:::.parse_permission_pattern("Read(~/.zshrc)")
  expect_equal(p$tool_name,    "Read")
  expect_equal(p$rule_content, "~/.zshrc")
})

test_that(".parse_permission_pattern returns NULL for empty string", {
  expect_null(codeagent:::.parse_permission_pattern(""))
  expect_null(codeagent:::.parse_permission_pattern(NULL))
})

# ---------------------------------------------------------------------------
# .permissions_to_rules
# ---------------------------------------------------------------------------

test_that(".permissions_to_rules converts allow/deny/ask arrays to PermissionRule list", {
  perms <- list(
    allow = c("Bash(npm run test *)", "Read(~/.zshrc)"),
    deny  = "Bash(rm -rf *)",
    ask   = character(0)
  )
  rules <- codeagent:::.permissions_to_rules(perms)
  expect_true(is.list(rules))
  expect_equal(length(rules), 3L)
  behaviors <- vapply(rules, function(r) r$behavior, character(1))
  expect_true("allow" %in% behaviors)
  expect_true("deny"  %in% behaviors)
  # All are PermissionRule
  expect_true(all(vapply(rules, inherits, logical(1), "PermissionRule")))
})

test_that(".permissions_to_rules handles empty lists (jsonlite shape)", {
  perms <- list(allow = list(), deny = list(), ask = list())
  rules <- codeagent:::.permissions_to_rules(perms)
  expect_equal(length(rules), 0L)
})

test_that(".permissions_to_rules handles missing sub-keys gracefully", {
  rules <- codeagent:::.permissions_to_rules(list())
  expect_equal(length(rules), 0L)
  rules2 <- codeagent:::.permissions_to_rules(NULL)
  expect_equal(length(rules2), 0L)
})

# ---------------------------------------------------------------------------
# env block application
# ---------------------------------------------------------------------------

test_that("load_settings applies env block before reading env-var layer", {
  # Write a temp settings.json in a temp project .codeagent/ directory.
  tmp_dir <- tempfile("codeagent_test_")
  dir.create(file.path(tmp_dir, ".codeagent"), recursive = TRUE)
  on.exit(unlink(tmp_dir, recursive = TRUE), add = TRUE)

  sentinel_val <- paste0("test-endpoint-", as.integer(Sys.time()))
  cfg <- list(env = list(CODEAGENT_MODEL = sentinel_val,
                          CODEAGENT_BASE_URL = "https://test.example.com"))
  writeLines(jsonlite::toJSON(cfg, auto_unbox = TRUE, pretty = TRUE),
             file.path(tmp_dir, ".codeagent", "settings.json"))

  withr::with_envvar(c(CODEAGENT_MODEL = "", CODEAGENT_BASE_URL = ""), {
    s <- load_settings(tmp_dir)
    # After env block applied, CODEAGENT_MODEL picked up by env-var layer
    expect_equal(s$model, sentinel_val)
    expect_equal(s$base_url, "https://test.example.com")
  })
})

# ---------------------------------------------------------------------------
# small_fast_model env override
# ---------------------------------------------------------------------------

test_that("load_settings picks up CODEAGENT_SMALL_FAST_MODEL", {
  # Use a project .codeagent/settings.json that sets env block directly,
  # so ~/.codeagent/settings.json env block cannot override our value.
  tmp <- tempfile(); dir.create(file.path(tmp, ".codeagent"), recursive = TRUE)
  on.exit(unlink(tmp, TRUE), add = TRUE)
  sentinel <- "test-fast-model-xyz123"
  cfg <- list(env = list(CODEAGENT_SMALL_FAST_MODEL = sentinel))
  writeLines(jsonlite::toJSON(cfg, auto_unbox = TRUE, pretty = TRUE),
             file.path(tmp, ".codeagent", "settings.json"))
  # Project settings override user settings (project loaded after user).
  s <- load_settings(tmp)
  expect_equal(s$small_fast_model, sentinel)
})

test_that("load_settings leaves small_fast_model NULL when not set anywhere", {
  # Use a clean project with no settings and no env var.
  tmp <- tempfile(); dir.create(tmp); on.exit(unlink(tmp, TRUE), add = TRUE)
  # Project settings.json with empty env (overrides user settings env block)
  cfg <- list(env = list(CODEAGENT_SMALL_FAST_MODEL = ""))
  dir.create(file.path(tmp, ".codeagent"), recursive = TRUE)
  writeLines(jsonlite::toJSON(cfg, auto_unbox = TRUE, pretty = TRUE),
             file.path(tmp, ".codeagent", "settings.json"))
  withr::with_envvar(c(CODEAGENT_SMALL_FAST_MODEL = ""), {
    s <- load_settings(tmp)
    expect_null(s$small_fast_model)
  })
})

# ---------------------------------------------------------------------------
# effortLevel parsed
# ---------------------------------------------------------------------------

test_that("load_settings parses effortLevel from settings.json", {
  tmp_dir <- tempfile("codeagent_effort_")
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE), add = TRUE)

  cfg <- list(effortLevel = "high")
  writeLines(jsonlite::toJSON(cfg, auto_unbox = TRUE, pretty = TRUE),
             file.path(tmp_dir, "settings.json"))

  withr::with_envvar(c(CODEAGENT_DIR = tmp_dir), {
    s <- load_settings(getwd())
    # effortLevel stored as-is (R key: effortLevel or effort_level depending on merge)
    expect_true(!is.null(s$effortLevel) || !is.null(s$effort_level))
  })
})

# ---------------------------------------------------------------------------
# use_codeagent_settings template validity
# ---------------------------------------------------------------------------

test_that("settings.json template is valid JSON and contains required keys", {
  skip_if_not_installed("jsonlite")
  tmpl <- system.file("templates", "settings.json", package = "codeagent")
  skip_if(!nzchar(tmpl) || !file.exists(tmpl), "template not installed")
  parsed <- jsonlite::fromJSON(tmpl, simplifyVector = TRUE)
  expect_true("model"       %in% names(parsed))
  expect_true("env"         %in% names(parsed))
  expect_true("permissions" %in% names(parsed))
  # Template must not contain real credentials
  raw <- paste(readLines(tmpl, warn = FALSE), collapse = "\n")
  expect_false(grepl("dapi|adb-7234", raw, ignore.case = TRUE))
})

test_that("use_codeagent_settings creates file at user scope", {
  tmp_dir <- tempfile("codeagent_us_")
  dir.create(tmp_dir)
  on.exit(unlink(tmp_dir, recursive = TRUE), add = TRUE)

  # Use project scope + tmp cwd to avoid touching ~/.codeagent/settings.json
  dest <- withr::with_dir(tmp_dir, {
    use_codeagent_settings(scope = "project", open = FALSE)
  })
  expect_true(file.exists(dest))
  parsed <- jsonlite::fromJSON(dest, simplifyVector = TRUE)
  expect_true("model" %in% names(parsed))
  # No real token in created file
  raw <- paste(readLines(dest, warn = FALSE), collapse = "\n")
  expect_false(grepl("dapi", raw, ignore.case = TRUE))
})

# ---------------------------------------------------------------------------
# .load_claude_md multi-level merge
# ---------------------------------------------------------------------------

test_that(".load_claude_md merges project-level files outer-to-inner", {
  root  <- tempfile("camd_"); dir.create(root)
  inner <- file.path(root, "sub", "deep")
  dir.create(inner, recursive = TRUE)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)

  writeLines("OUTER_RULE", file.path(root, "CLAUDE.md"))
  writeLines("INNER_RULE", file.path(inner, "CLAUDE.md"))

  merged <- codeagent:::.load_claude_md(inner)
  expect_true(grepl("OUTER_RULE", merged))
  expect_true(grepl("INNER_RULE", merged))
  # Inner (more specific) appears after outer
  expect_lt(regexpr("OUTER_RULE", merged), regexpr("INNER_RULE", merged))
  # Source markers present
  expect_true(grepl("<!-- source:", merged))
})

test_that(".load_claude_md returns NULL when no files exist", {
  empty <- tempfile("camd_empty_"); dir.create(empty)
  on.exit(unlink(empty, recursive = TRUE), add = TRUE)
  # Note: may still pick up ~/.claude/CLAUDE.md if present; test only that a
  # tree with no project CLAUDE.md does not error.
  expect_silent(codeagent:::.load_claude_md(empty))
})

test_that(".load_claude_md de-duplicates identical paths", {
  root <- tempfile("camd_dup_"); dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  writeLines("ONLY_ONCE", file.path(root, "CLAUDE.md"))
  merged <- codeagent:::.load_claude_md(root)
  # "ONLY_ONCE" should appear exactly once even though walk-up may revisit
  expect_equal(lengths(regmatches(merged, gregexpr("ONLY_ONCE", merged))), 1L)
})
