# tests/testthat/test-data-shield-schema.R
# Data Shield schema injection into the system prompt (policy visibility,
# problem A): schema_block builder + .build_system_prompt wiring +
# refresh_data_shield_context runtime rebuild. Aligns with querychat's
# schema-in-system-prompt pattern; DescribeData tool is retained as the live
# fallback.

make_shield <- function() {
  sh <- DataShield$new(strategies = list(shield_describe(),
                                         shield_egress(max_rows = 0L)))
  sh$register_data(
    data.frame(subject_id = sprintf("SUBJECT%03d", 1:50),
               arm = rep(c("Placebo", "Drug"), 25),
               value = runif(50), stringsAsFactors = FALSE),
    name = "D0")
  sh
}

test_that("schema_block renders one registered dataset with filtered schema", {
  sh <- make_shield()
  b <- sh$schema_block()
  expect_true(grepl("<protected-data>", b, fixed = TRUE))
  expect_true(grepl("Protected dataset 'D0'", b, fixed = TRUE))
  expect_true(grepl("subject_id", b, fixed = TRUE))
  expect_true(grepl("sensitivity=identifier", b, fixed = TRUE))
})

test_that("schema_block suppresses identifier values (no raw leak)", {
  sh <- make_shield()
  b <- sh$schema_block()
  expect_false(grepl("SUBJECT001", b, fixed = TRUE))   # identifier value gone
  expect_true(grepl("values=suppressed", b, fixed = TRUE))
})

test_that("schema_block grows as datasets are registered (live engine state)", {
  sh <- make_shield()
  expect_false(grepl("D1", sh$schema_block(), fixed = TRUE))
  sh$register_data(data.frame(site = sprintf("SITE%02d", 1:30)), name = "D1")
  b <- sh$schema_block()
  expect_true(grepl("Protected dataset 'D0'", b, fixed = TRUE))
  expect_true(grepl("Protected dataset 'D1'", b, fixed = TRUE))
})

test_that("schema_block returns '' with no datasets", {
  sh <- DataShield$new(strategies = list(shield_describe(),
                                         shield_egress(max_rows = 0L)))
  expect_identical(sh$schema_block(), "")
})

test_that("schema_block returns '' when DescribeData disabled", {
  # No shield_describe() -> describe_enabled FALSE.
  sh <- DataShield$new(strategies = list(shield_egress(max_rows = 0L)))
  sh$register_data(data.frame(x = sprintf("V%03d", 1:50)), name = "D0")
  expect_identical(sh$schema_block(), "")
})

test_that(".build_system_prompt injects <protected-data> when a shield is active", {
  sh <- make_shield()
  sp <- codeagent:::.build_system_prompt(
    list(data_shield_engine = sh, permission_mode = "bypass"), getwd())
  expect_true(grepl("<protected-data>", sp, fixed = TRUE))
  expect_true(grepl("Protected dataset 'D0'", sp, fixed = TRUE))
})

test_that(".build_system_prompt omits the block without a shield", {
  sp <- codeagent:::.build_system_prompt(
    list(permission_mode = "bypass"), getwd())
  expect_false(grepl("<protected-data>", sp, fixed = TRUE))
})

test_that("refresh_data_shield_context rebuilds the prompt with new datasets, keeps history", {
  skip_if_not_installed("ellmer")
  sh <- make_shield()
  chat <- ellmer::chat_openai_compatible(
    base_url = "http://x", model = "m", credentials = function() "k")
  client <- structure(
    list(chat = chat,
         settings = list(data_shield_engine = sh, permission_mode = "bypass",
                         cwd = getwd())),
    class = "CodeagentClient")
  chat$set_system_prompt(
    codeagent:::.build_system_prompt(client$settings, getwd()))
  chat$set_turns(list(ellmer::Turn("user", "hi"),
                      ellmer::Turn("assistant", "hello")))

  expect_true(grepl("D0", chat$get_system_prompt(), fixed = TRUE))
  expect_false(grepl("D1", chat$get_system_prompt(), fixed = TRUE))

  sh$register_data(data.frame(site = sprintf("SITE%02d", 1:30)), name = "D1")
  refresh_data_shield_context(client)

  expect_true(grepl("D0", chat$get_system_prompt(), fixed = TRUE))
  expect_true(grepl("D1", chat$get_system_prompt(), fixed = TRUE))  # new dataset in
  expect_length(chat$get_turns(), 2L)                               # history intact
})

test_that("refresh_data_shield_context is a safe no-op on a bare non-Chat", {
  expect_invisible(refresh_data_shield_context(structure(list(), class = "CodeagentClient")))
})
