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

test_that("a ContentToolResult with a structured value is sent as one JSON string", {
  res <- ellmer::ContentToolResult(
    value = list(note = "x", table = data.frame(a = 1:2, b = c("u", NA))),
    extra = list(display = list(title = "kept")))
  out <- .normalize_tool_output(res)
  expect_type(out@value, "character")
  expect_length(out@value, 1L)
  back <- jsonlite::fromJSON(out@value)
  expect_equal(back$table$a, 1:2)
  expect_true(is.na(back$table$b[2]))
  expect_identical(out@extra$display$title, "kept")
})

test_that("string and scalar ContentToolResult values are left alone", {
  s <- ellmer::ContentToolResult(value = "text")
  expect_identical(.normalize_tool_output(s), s)
  n <- ellmer::ContentToolResult(value = 3)
  expect_identical(.normalize_tool_output(n), n)
})

test_that("a value JSON cannot encode is sent as its printed text, never as a list", {
  tb <- ellmer::ContentToolResult(value = list(counts = table(c("a", "b", "a"))),
                                  extra = list(display = list(title = "kept")))
  out <- .normalize_tool_output(tb)
  expect_type(out@value, "character")
  expect_length(out@value, 1L)
  expect_identical(out@extra$display$title, "kept")
  f <- .normalize_tool_output(ellmer::ContentToolResult(value = list(fn = function() 1)))
  expect_type(f@value, "character")
  big <- .tool_value_printed(paste(rep("x", 30000), collapse = ""))
  expect_match(big, "truncated", fixed = TRUE)
})

test_that("a host card holding render hooks is recorded as static HTML", {
  skip_if_not_installed("bslib")
  card <- bslib::card(bslib::card_header("Head"), bslib::card_body(htmltools::tags$p("Body")))
  res <- ellmer::ContentToolResult(value = "ok", extra = list(
    display = list(title = "t", html = htmltools::div(id = "x1", card)),
    meta = list(button_id = "x1", n = 1L)))
  expect_true(.holds_closure(res@extra))
  out <- .normalize_tool_output(res)
  expect_false(.holds_closure(out@extra))
  html <- out@extra$display$html$children[[1]]     # inside the result-id wrapper
  expect_s3_class(html, "html")
  expect_match(as.character(html), "bslib-card", fixed = TRUE)
  expect_match(as.character(html), "id=\"x1\"", fixed = TRUE)
  expect_true(length(htmltools::htmlDependencies(html)) > 0)
  expect_identical(out@extra$meta, list(button_id = "x1", n = 1L))      # untouched
  # the conversation can be recorded (shinychat history / session log)
  rec <- ellmer::contents_record(ellmer::Turn("user", list(out)))
  expect_type(jsonlite::serializeJSON(rec), "character")
})

test_that("results without render hooks are not touched", {
  disp <- list(title = "t", html = htmltools::div(class = "a", "x"))
  res <- ellmer::ContentToolResult(value = "ok", extra = list(display = disp))
  out <- .normalize_tool_output(res)@extra$display
  expect_identical(out$html$children[[1]], disp$html)     # only wrapped with the result id
  expect_identical(out$title, disp$title)
})

test_that("tool results with an HTML card carry a result id for on_tool_open", {
  req <- ellmer::ContentToolRequest(id = "c1", name = "host_tool", arguments = list())
  res <- ellmer::ContentToolResult(value = "ok", request = req, extra = list(
    display = list(title = "t", html = htmltools::div("card")), meta = list(k = 1L)))
  out <- .normalize_tool_output(res)
  id <- out@extra$codeagent$result_id
  expect_match(id, "^car_[0-9a-f]{32}$")
  html <- as.character(out@extra$display$html)
  expect_match(html, sprintf("data-ca-result=\"%s\"", id), fixed = TRUE)
  expect_match(html, "<div>card</div>", fixed = TRUE)
  expect_identical(out@extra$meta, list(k = 1L))
  # idempotent; text-only results are not marked
  expect_identical(.mark_tool_result(out)@extra$codeagent$result_id, id)
  txt <- .normalize_tool_output(ellmer::ContentToolResult(value = "ok", extra = list(display = list(markdown = "x"))))
  expect_null(txt@extra$codeagent$result_id)
  # found in the turns; the id survives recording (restored conversations)
  turns <- list(ellmer::Turn("user", list(out)))
  expect_identical(.find_tool_result(turns, id)@value, "ok")
  expect_null(.find_tool_result(turns, "car_nope")); expect_null(.find_tool_result(turns, NULL))
  back <- ellmer::contents_replay(ellmer::contents_record(turns[[1]]))
  expect_identical(.find_tool_result(list(back), id)@extra$codeagent$result_id, id)
})

test_that("codeagent_server checks on_tool_open", {
  expect_error(codeagent_server(NULL, NULL, NULL, client = structure(list(), class = "CodeagentClient"),
                                on_tool_open = "x"), "on_tool_open")
})
