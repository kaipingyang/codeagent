# Output-panel code preview (.code_preview / .editor_language)

test_that(".editor_language maps known extensions and defaults unknown to plain", {
  expect_equal(codeagent:::.editor_language("py"),  "python")
  expect_equal(codeagent:::.editor_language("R"),   "r")     # case-insensitive
  expect_equal(codeagent:::.editor_language("ts"),  "typescript")
  expect_equal(codeagent:::.editor_language("rs"),  "rust")
  expect_equal(codeagent:::.editor_language("yml"), "yaml")
  # unknown / empty extension must fall back to "plain", never NA
  expect_equal(codeagent:::.editor_language("zzz"), "plain")
  expect_equal(codeagent:::.editor_language(""),    "plain")
})

test_that(".code_preview renders a read-only input_code_editor for code files", {
  tf <- tempfile(fileext = ".py")
  writeLines(c("def f(x):", "    return x + 1"), tf)
  html <- as.character(codeagent:::.code_preview(tf, "py"))
  expect_match(html, "bslib-code-editor")
  expect_match(html, 'language="python"')
  expect_match(html, "readonly=\"true\"")
  expect_match(html, "line-numbers=\"true\"")
})

test_that(".code_preview tolerates unreadable paths without erroring", {
  expect_no_error(codeagent:::.code_preview(tempfile(fileext = ".xyz"), "xyz"))
})
