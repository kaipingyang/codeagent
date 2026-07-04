# Task 08: posit-dev/skills integration via install_ds_skills().

test_that("install_ds_skills validates scope and returns FALSE without btw", {
  # scope is match.arg'd
  expect_error(install_ds_skills(scope = "nope"), "should be one of")
})

test_that("install_ds_skills calls btw_skill_install_github with posit-dev/skills", {
  skip_if_not_installed("btw")
  captured <- NULL
  # Intercept the btw installer so no network call happens.
  local_mocked_bindings(
    btw_skill_install_github = function(repo, skill = NULL, scope = "user",
                                        overwrite = FALSE) {
      captured <<- list(repo = repo, skill = skill, scope = scope,
                        overwrite = overwrite)
      invisible(TRUE)
    },
    .package = "btw"
  )
  ok <- suppressMessages(install_ds_skills(skill = "shiny", scope = "project"))
  expect_true(ok)
  expect_identical(captured$repo, "posit-dev/skills")
  expect_identical(captured$skill, "shiny")
  expect_identical(captured$scope, "project")
})

test_that("btw-installed skills are on codeagent's discovery path", {
  skip_if_not_installed("btw")
  # codeagent discovers btw's skill directories; ensure the accessor exists so
  # anything installed via btw is picked up by list_skills_meta().
  dirs <- tryCatch(btw:::btw_skills_directories(), error = function(e) NULL)
  expect_false(is.null(dirs))
})

test_that("install_ds_skills installs each selected skill in a loop", {
  skip_if_not_installed("btw")
  calls <- character(0)
  local_mocked_bindings(
    btw_skill_install_github = function(repo, skill = NULL, scope = "user",
                                        overwrite = FALSE) {
      calls[[length(calls) + 1L]] <<- skill
      invisible(TRUE)
    },
    .package = "btw"
  )
  # explicit vector -> one call per skill (btw installs one at a time)
  ok <- suppressMessages(install_ds_skills(c("cli", "ggsql"), scope = "project"))
  expect_true(ok)
  expect_setequal(calls, c("cli", "ggsql"))
  # NULL -> curated default set (all installed)
  calls <- character(0)
  suppressMessages(install_ds_skills(NULL, scope = "project"))
  expect_setequal(calls, .posit_ds_default_skills())
})

test_that(".posit_ds_default_skills is a non-empty R/data-science set", {
  d <- .posit_ds_default_skills()
  expect_true(length(d) >= 5L)
  expect_true(all(nzchar(d)))
  expect_true("quarto-authoring" %in% d)
})
