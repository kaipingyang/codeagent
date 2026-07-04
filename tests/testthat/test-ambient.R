# Tests for gander-style ambient R-environment context injection
# (.r_env_context + .build_system_reminder opt-in).

test_that(".r_env_context summarises data.frames in GlobalEnv", {
  assign("amb_df_test", data.frame(a = 1:3, b = letters[1:3]), envir = .GlobalEnv)
  on.exit(rm("amb_df_test", envir = .GlobalEnv), add = TRUE)
  ctx <- .r_env_context()
  expect_true(grepl("amb_df_test", ctx, fixed = TRUE))
  expect_true(grepl("a:integer", ctx, fixed = TRUE))
  expect_true(grepl("3x2", ctx, fixed = TRUE))   # 3 rows x 2 cols
})

test_that(".r_env_context respects the max_chars cap", {
  assign("amb_df_test", data.frame(a = 1:3), envir = .GlobalEnv)
  on.exit(rm("amb_df_test", envir = .GlobalEnv), add = TRUE)
  ctx <- .r_env_context(max_chars = 20L)
  expect_lte(nchar(ctx), 20L + nchar("\n  ... (truncated)"))
  expect_true(grepl("truncated", ctx, fixed = TRUE))
})

test_that("build_system_reminder injects env only when ambient is enabled", {
  assign("amb_df_test", data.frame(a = 1:3), envir = .GlobalEnv)
  on.exit(rm("amb_df_test", envir = .GlobalEnv), add = TRUE)

  # Off by default (no flag, no option): no GlobalEnv block.
  withr::local_options(codeagent.ambient_context = NULL)
  r_off <- .build_system_reminder(list(), iteration = 1L, cwd = tempdir())
  expect_false(grepl("R session objects", r_off, fixed = TRUE))

  # Enabled via option.
  withr::local_options(codeagent.ambient_context = TRUE)
  r_on <- .build_system_reminder(list(), iteration = 1L, cwd = tempdir())
  expect_true(grepl("R session objects", r_on, fixed = TRUE))

  # Enabled via settings flag.
  r_on2 <- .build_system_reminder(list(inject_r_env = TRUE), iteration = 1L,
                                  cwd = tempdir())
  expect_true(grepl("R session objects", r_on2, fixed = TRUE))
})

test_that("ambient injection only happens on the first iteration", {
  assign("amb_df_test", data.frame(a = 1:3), envir = .GlobalEnv)
  on.exit(rm("amb_df_test", envir = .GlobalEnv), add = TRUE)
  withr::local_options(codeagent.ambient_context = TRUE)
  r2 <- .build_system_reminder(list(), iteration = 2L, cwd = tempdir())
  expect_false(grepl("R session objects", r2, fixed = TRUE))
})
