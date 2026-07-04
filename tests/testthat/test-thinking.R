# Task 04: native thinking. Verify .make_chat wires params(reasoning_effort=)
# and preserve_thinking for the openai_compatible provider without error
# (ellmer validates these at chat construction; no network call is made).

test_that(".make_chat builds an openai_compatible chat with reasoning_effort", {
  withr::local_envvar(CODEAGENT_API_KEY = "dummy")
  s <- list(provider = "openai_compatible", base_url = "http://localhost:1/x",
            model = "some-model", effort_level = "high")
  chat <- tryCatch(.make_chat(s), error = function(e) e)
  expect_s3_class(chat, "Chat")
})

test_that(".make_chat builds fine without effort_level (no params)", {
  withr::local_envvar(CODEAGENT_API_KEY = "dummy")
  s <- list(provider = "openai_compatible", base_url = "http://localhost:1/x",
            model = "some-model")
  chat <- tryCatch(.make_chat(s), error = function(e) e)
  expect_s3_class(chat, "Chat")
})

test_that("ellmer exposes the native thinking primitives we rely on", {
  expect_true("reasoning_effort" %in% names(formals(ellmer::params)))
  expect_true("preserve_thinking" %in% names(formals(ellmer::chat_openai_compatible)))
  expect_true(exists("ContentThinking", where = asNamespace("ellmer")))
})
