# max_budget_usd (P5 backlog): codeagent_client() validation + settings
# threading. The BudgetTracker/should_stop() logic itself is covered in
# tests/testthat/test-budget.R; this file only exercises the client-facing
# wiring (argument validation, default-preservation, env var override).

.budget_test_chat <- function() {
  ellmer::chat_openai_compatible(
    base_url = "http://x", model = "m", credentials = function() "k")
}

test_that("codeagent_client() rejects a non-positive/non-numeric max_budget_usd", {
  chat <- .budget_test_chat()
  expect_error(codeagent_client(chat, register_tools = FALSE, max_budget_usd = 0),
               "positive number")
  expect_error(codeagent_client(chat, register_tools = FALSE, max_budget_usd = -1),
               "positive number")
  expect_error(codeagent_client(chat, register_tools = FALSE, max_budget_usd = "5"),
               "positive number")
  expect_error(codeagent_client(chat, register_tools = FALSE, max_budget_usd = c(1, 2)),
               "positive number")
})

test_that("codeagent_client() threads an explicit max_budget_usd into settings", {
  chat <- .budget_test_chat()
  client <- codeagent_client(chat, register_tools = FALSE, max_budget_usd = 2.5)
  expect_identical(client$settings$max_budget_usd, 2.5)
})

test_that("codeagent_client()'s NULL default preserves settings.json's value", {
  d <- withr::local_tempdir()
  dir.create(file.path(d, ".codeagent"))
  writeLines('{"max_budget_usd": 10.0}', file.path(d, ".codeagent", "settings.json"))

  chat <- .budget_test_chat()
  client <- codeagent_client(chat, cwd = d, register_tools = FALSE)
  expect_identical(client$settings$max_budget_usd, 10)
})

test_that("CODEAGENT_MAX_BUDGET_USD env var sets the default when settings.json has none", {
  withr::local_envvar(CODEAGENT_MAX_BUDGET_USD = "7.5")
  settings <- load_settings(withr::local_tempdir())
  expect_equal(settings$max_budget_usd, 7.5)
})

test_that("max_budget_usd defaults to NULL (no cap) with no env/settings override", {
  withr::local_envvar(CODEAGENT_MAX_BUDGET_USD = NA)
  settings <- load_settings(withr::local_tempdir())
  expect_null(settings$max_budget_usd)
})
