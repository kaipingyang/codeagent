# Tests for Path A btw file tool permission wrapping (R/tools_btw_files_pathA.R).
# The wrapper extracts the underlying fn via S7::S7_data(), gates it with the
# codeagent permission checker, and rebuilds an ellmer tool.

# A stand-in "btw" write tool: an ellmer ToolDef whose S7 data is the fn.
.fake_btw_write_tool <- function(name = "btw_tool_files_write") {
  ellmer::tool(
    fun = function(path, content, `_intent` = NULL) paste0("WROTE:", path, "=", content),
    name = name,
    description = "fake btw write tool",
    arguments = list(
      path      = ellmer::type_string("p"),
      content   = ellmer::type_string("c"),
      `_intent` = ellmer::type_string("i", required = FALSE)
    ),
    annotations = ellmer::tool_annotations(title = name, read_only_hint = FALSE)
  )
}

test_that("S7_data extracts the underlying function from an ellmer ToolDef", {
  t  <- .fake_btw_write_tool()
  fn <- S7::S7_data(t)
  expect_true(is.function(fn))
  expect_identical(fn(path = "/a.txt", content = "x"), "WROTE:/a.txt=x")
})

test_that(".wrap_btw_tool_permission allows in bypass mode and runs the fn", {
  wrapped <- .wrap_btw_tool_permission(.fake_btw_write_tool(), mode = "bypass")
  expect_true(is.function(wrapped))
  expect_identical(wrapped@name, "btw_tool_files_write")
  out <- wrapped(path = "/a.txt", content = "hi")
  # bypass -> fn runs, returns its plain string result
  expect_identical(out, "WROTE:/a.txt=hi")
})

test_that(".wrap_btw_tool_permission denies write tools in plan mode", {
  wrapped <- .wrap_btw_tool_permission(.fake_btw_write_tool(), mode = "plan")
  out <- wrapped(path = "/a.txt", content = "hi")
  # plan -> non-readonly denied -> ContentToolResult with denial message
  val <- tryCatch(out@value, error = function(e) as.character(out))
  expect_true(grepl("Permission denied", val, fixed = TRUE))
})

test_that(".wrap_btw_tool_permission denies in default mode without ask_fn", {
  wrapped <- .wrap_btw_tool_permission(.fake_btw_write_tool(), mode = "default",
                                       ask_fn = NULL)
  out <- wrapped(path = "/a.txt", content = "hi")
  val <- tryCatch(out@value, error = function(e) as.character(out))
  expect_true(grepl("Permission denied", val, fixed = TRUE))
})

test_that(".wrap_btw_tool_permission allows in default mode when ask_fn says yes", {
  wrapped <- .wrap_btw_tool_permission(.fake_btw_write_tool(), mode = "default",
                                       ask_fn = function(name, input) TRUE)
  out <- wrapped(path = "/a.txt", content = "hi")
  expect_identical(out, "WROTE:/a.txt=hi")
})

test_that("_intent is excluded from the permission check args", {
  # The checker must receive args WITHOUT _intent. We capture what the checker
  # sees via a custom ask_fn (default mode -> ask).
  seen <- NULL
  wrapped <- .wrap_btw_tool_permission(.fake_btw_write_tool(), mode = "default",
    ask_fn = function(name, input) { seen <<- input; TRUE })
  wrapped(path = "/a.txt", content = "hi", `_intent` = "because")
  expect_false("_intent" %in% names(seen))
  expect_true(all(c("path", "content") %in% names(seen)))
})

test_that("register_btw_file_tools registers read direct + write gated", {
  skip_if_not_installed("btw")
  chat <- ellmer::chat_openai_compatible(base_url = "http://x", model = "m",
                                         credentials = function() "k")
  n <- suppressMessages(suppressWarnings(
    register_btw_file_tools(chat, mode = "bypass")))
  expect_true(n >= 1L)
  tools <- chat$get_tools()
  nms   <- vapply(tools, function(x) x@name, character(1))
  # At least one read tool present (registered directly).
  expect_true(any(nms %in% .BTW_FILE_READONLY))
})
