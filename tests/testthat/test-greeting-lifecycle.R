test_that("chat shell uses one persistent shinychat greeting", {
  captured <- NULL
  testthat::with_mocked_bindings(
    {
      chat_codeagent_ui(NULL)
    },
    chat_ui = function(id, ..., greeting = NULL) {
      captured <<- greeting
      htmltools::tags$div(id = id)
    },
    .package = "shinychat"
  )
  expect_s3_class(captured, "chat_greeting")
  expect_true(captured$persistent)
  expect_match(captured$content, "codeagent", fixed = TRUE)
})

test_that("codeagent_app greeting remains a composer-prefill argument", {
  expect_true("greeting" %in% names(formals(codeagent_app)))
  expect_null(formals(codeagent_app)$greeting)
  implementation <- paste(deparse(body(codeagent_app)), collapse = "\n")
  expect_true(grepl(
    "update_chat_user_input\\(\"chat\",\\s+value = greeting",
    implementation, perl = TRUE))
})


test_that("chat shell disables external citation favicon prefetch", {
  ui <- chat_codeagent_ui(NULL)
  html <- htmltools::renderTags(ui)$html
  expect_match(html, 'aside-favicon="false"', fixed = TRUE)
})
