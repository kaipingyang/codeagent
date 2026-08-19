normalization_tool <- function(value) {
  ellmer::tool(function() value, name = "fixture_normalize",
               description = "normalization fixture", arguments = list())
}

test_that("data.frame and list results become deterministic ContentToolResult", {
  df <- .normalize_tool_output(data.frame(a = 1:2, b = c("x", "y")))
  expect_true(S7::S7_inherits(df, ellmer::ContentToolResult))
  expect_identical(df@extra$codeagent$artifact$kind, "table")
  expect_match(as.character(df@value), '"a"', fixed = TRUE)

  x <- .normalize_tool_output(list(ok = TRUE, values = 1:3))
  expect_true(S7::S7_inherits(x, ellmer::ContentToolResult))
  expect_match(as.character(x@value), '"ok"', fixed = TRUE)
})

test_that("normalized ellmer Content and image-like results remain unchanged", {
  text <- ellmer::ContentText("hello")
  result <- ellmer::ContentToolResult(value = "already normalized")
  expect_identical(.normalize_tool_output(text), text)
  expect_identical(.normalize_tool_output(result), result)
})

test_that("unserializable complex results degrade to a fixed safe error", {
  bad <- list(secret = "DO_NOT_ECHO", fn = function() "DO_NOT_ECHO")
  result <- expect_no_error(.normalize_tool_output(bad))
  expect_true(S7::S7_inherits(result, ellmer::ContentToolResult))
  expect_identical(result@extra$codeagent$artifact$kind, "error")
  expect_false(grepl("DO_NOT_ECHO", as.character(result@value), fixed = TRUE))
})

test_that("tool normalizer wraps once and preserves scalar results", {
  tool <- normalization_tool(data.frame(a = 1L))
  wrapped <- .normalize_tool_def_result(tool)
  output <- S7::S7_data(wrapped)()
  expect_true(S7::S7_inherits(output, ellmer::ContentToolResult))
  again <- .normalize_tool_def_result(wrapped)
  expect_identical(S7::S7_data(again), S7::S7_data(wrapped))

  scalar <- normalization_tool("plain")
  expect_identical(S7::S7_data(.normalize_tool_def_result(scalar))(), "plain")
})

test_that("promise tool results normalize after fulfillment", {
  promise <- promises::promise_resolve(list(ok = TRUE))
  normalized <- .normalize_tool_output(promise)
  expect_true(promises::is.promise(normalized))
  value <- NULL
  promises::then(normalized, function(x) value <<- x)
  for (i in 1:20) { later::run_now(0.01); if (!is.null(value)) break }
  expect_true(S7::S7_inherits(value, ellmer::ContentToolResult))
})
