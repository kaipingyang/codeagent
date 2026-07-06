test_that(".tool_capability classifies tools (unknown -> read/allow)", {
  expect_identical(.tool_capability("Write"), "write")
  expect_identical(.tool_capability("Read"), "read")
  expect_identical(.tool_capability("Bash"), "exec")
  expect_identical(.tool_capability("Format"), "write")
  expect_identical(.tool_capability("btw_tool_git_commit"), "write")
  expect_identical(.tool_capability("btw_tool_github"), "net")
  expect_identical(.tool_capability("btw_tool_files_read"), "read")
  expect_identical(.tool_capability("some_unknown_tool"), "read")
})

test_that(".resolve_tool_policy parses settings$tools with defaults", {
  p <- .resolve_tool_policy(list(tools = list(
    sets = c("A"), capabilities = list(write = "ask"),
    overrides = list(Bash = "deny"))))
  expect_identical(p$sets, "A")
  expect_identical(p$capabilities$write, "ask")
  expect_identical(p$overrides$Bash, "deny")

  p2 <- .resolve_tool_policy(list())
  expect_setequal(p2$sets, c("A", "B"))
  expect_identical(p2$overrides, list())
})

test_that(".gate_decide precedence: override > capability > check_permission", {
  pol <- list(overrides = list(Write = "deny"), capabilities = list(write = "ask"))
  expect_identical(.gate_decide("Write", list(), pol, "bypass", list(), "write"), "deny")

  pol2 <- list(overrides = list(), capabilities = list(write = "ask"))
  expect_identical(.gate_decide("Write", list(), pol2, "bypass", list(), "write"), "ask")

  pol3 <- list(overrides = list(), capabilities = list())
  # falls back to check_permission; bypass mode -> allow
  expect_identical(.gate_decide("Write", list(), pol3, "bypass", list(), "write"), "allow")
})

test_that(".install_permission_gate registers on the chat without error", {
  chat <- ellmer::chat_openai_compatible(
    base_url = "http://x", model = "m", credentials = function() "k")
  me <- new.env(); me$mode <- "default"
  expect_invisible(
    .install_permission_gate(chat, list(), me, list(), ask_fn = NULL))
})
