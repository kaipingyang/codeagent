
test_that("workspace tabs can float as windows over the page", {
  js <- paste(readLines(system.file("www", "workspace.js", package = "codeagent")), collapse = "\n")
  for (k in c("floatTab", "dockTab", "Pop out", "dblclick", "is-floating")) expect_match(js, k, fixed = TRUE)
  css <- paste(readLines(system.file("www", "styles.css", package = "codeagent")), collapse = "\n")
  expect_match(css, ".ca-ws-pane.is-floating", fixed = TRUE)
})
