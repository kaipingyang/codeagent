test_that("update_model_prices is explicit and reports updater result", {
  calls <- 0L
  testthat::local_mocked_bindings(
    .ellmer_price_updater = function() { calls <<- calls + 1L; TRUE }
  )
  result <- update_model_prices()
  expect_true(result$ok)
  expect_true(result$updated)
  expect_identical(calls, 1L)
})

test_that("price update network failure is nonfatal and sanitized", {
  testthat::local_mocked_bindings(
    .ellmer_price_updater = function() stop("secret.example.invalid?token=SECRET")
  )
  result <- expect_no_error(update_model_prices())
  expect_false(result$ok)
  expect_false(result$updated)
  expect_match(result$message, "could not be updated", fixed = TRUE)
  expect_false(grepl("secret|token", result$message, ignore.case = TRUE))
})
