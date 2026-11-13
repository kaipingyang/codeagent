# An explicit CODEAGENT_HOME is used as is: the one-time migration of a
# legacy ~/.codeagent must not copy the account's personal data into it.

test_that("an explicit CODEAGENT_HOME receives no legacy ~/.codeagent data", {
  home <- withr::local_tempdir()
  legacy <- file.path(home, ".codeagent")
  dir.create(file.path(legacy, "projects", "_tmp_personal"), recursive = TRUE)
  writeLines("{}", file.path(legacy, "settings.json"))
  app_home <- file.path(withr::local_tempdir(), "app_history")
  dir.create(app_home)
  withr::local_envvar(c(HOME = home, CODEAGENT_HOME = app_home))
  withr::local_options(codeagent._migrated = FALSE)

  expect_identical(.get_codeagent_dir(), app_home)
  expect_length(list.files(app_home, all.files = TRUE, no.. = TRUE), 0L)
  expect_true(file.exists(file.path(legacy, "settings.json")))
})

test_that("without CODEAGENT_HOME the legacy directory is still migrated", {
  home <- withr::local_tempdir()
  legacy <- file.path(home, ".codeagent")
  dir.create(legacy)
  writeLines("{}", file.path(legacy, "settings.json"))
  new_dir <- file.path(withr::local_tempdir(), "config")
  withr::local_envvar(c(HOME = home, CODEAGENT_HOME = ""))
  withr::local_options(codeagent._migrated = FALSE)
  local_mocked_bindings(.new_codeagent_dir = function() new_dir)

  expect_identical(.get_codeagent_dir(), new_dir)
  expect_true(file.exists(file.path(new_dir, "settings.json")))
})
