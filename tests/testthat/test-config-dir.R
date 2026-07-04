# Task 11: rappdirs config dir + one-time migration.

test_that(".migrate_config_dir copies a legacy tree into a fresh new dir", {
  old <- file.path(tempfile("old_"), "")
  new <- tempfile("new_")
  dir.create(old, recursive = TRUE)
  writeLines("x", file.path(old, "settings.json"))
  dir.create(file.path(old, "projects"))
  writeLines("s", file.path(old, "projects", "sess.jsonl"))

  did <- .migrate_config_dir(old, new, quiet = TRUE)
  expect_true(did)
  expect_true(file.exists(file.path(new, "settings.json")))
  expect_true(file.exists(file.path(new, "projects", "sess.jsonl")))
})

test_that(".migrate_config_dir is idempotent (no re-copy when new has content)", {
  old <- tempfile("old_"); new <- tempfile("new_")
  dir.create(old, recursive = TRUE); writeLines("x", file.path(old, "a.txt"))
  expect_true(.migrate_config_dir(old, new, quiet = TRUE))    # first: migrates
  # New now has content -> second call is a no-op.
  expect_false(.migrate_config_dir(old, new, quiet = TRUE))
})

test_that(".migrate_config_dir does nothing when legacy is absent", {
  old <- tempfile("nope_"); new <- tempfile("new_")
  expect_false(.migrate_config_dir(old, new, quiet = TRUE))
  expect_false(dir.exists(new))
})

test_that(".migrate_config_dir does nothing when old == new", {
  d <- tempfile("same_"); dir.create(d); writeLines("x", file.path(d, "a"))
  expect_false(.migrate_config_dir(d, d, quiet = TRUE))
})

test_that("CODEAGENT_HOME overrides the config dir", {
  ov <- tempfile("home_")
  withr::local_envvar(CODEAGENT_HOME = ov)
  expect_identical(.new_codeagent_dir(), ov)
})

test_that(".new_codeagent_dir uses rappdirs when available", {
  withr::local_envvar(CODEAGENT_HOME = "")
  skip_if_not_installed("rappdirs")
  expect_identical(.new_codeagent_dir(), rappdirs::user_config_dir("codeagent"))
})
