test_that(".otel_tracing_active reflects the otel tracer state", {
  testthat::local_mocked_bindings(
    is_tracing_enabled = function(tracer = NULL) TRUE, .package = "otel")
  expect_true(.otel_tracing_active())

  testthat::local_mocked_bindings(
    is_tracing_enabled = function(tracer = NULL) FALSE, .package = "otel")
  expect_false(.otel_tracing_active())
})

test_that(".with_codeagent_span runs the thunk with and without tracing", {
  # inactive -> thunk runs, no span opened
  testthat::local_mocked_bindings(
    is_tracing_enabled = function(tracer = NULL) FALSE, .package = "otel")
  expect_identical(.with_codeagent_span("x", list(), function() 42L), 42L)

  # active -> span opened once, thunk result still returned
  counter <- new.env(); counter$n <- 0L
  testthat::local_mocked_bindings(
    is_tracing_enabled = function(tracer = NULL) TRUE, .package = "otel")
  testthat::local_mocked_bindings(
    start_local_active_span = function(name = NULL, attributes = NULL, ...) {
      counter$n <- counter$n + 1L; invisible(NULL)
    }, .package = "otel")
  res <- .with_codeagent_span("codeagent.query", list(a = "b"), function() "ok")
  expect_identical(res, "ok")
  expect_identical(counter$n, 1L)
})

test_that("codeagent_otel_status reports structure and prints guidance", {
  s <- codeagent_otel_status()
  expect_s3_class(s, "codeagent_otel_status")
  expect_true(all(c("otel", "otelsdk", "tracing_active", "message") %in% names(s)))
  expect_true(is.logical(s$tracing_active))
  expect_true(nzchar(s$message))
  expect_output(print(s))
})
