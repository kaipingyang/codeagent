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

test_that(".tool_gate_fn fires PreToolUse + PermissionDenied and enforces deny", {
  reg <- HookRegistry$new()
  ev  <- new.env(); ev$log <- character()
  reg$register_pre(function(tool_name, tool_input)
    ev$log <- c(ev$log, paste0("PRE:", tool_name)))
  reg$register(HookEvent$PERMISSION_DENIED, function(tool_name, tool_input, mode)
    ev$log <- c(ev$log, paste0("DENIED:", tool_name)))

  policy <- list(overrides = list(Write = "deny"), capabilities = list())
  gate <- .tool_gate_fn(policy, function() "default", list(), ask_fn = NULL, hooks = reg)
  req  <- ellmer::ContentToolRequest(id = "1", name = "Write",
            arguments = list(file_path = "x", content = "y"))

  expect_error(gate(req), class = "ellmer_tool_reject")   # deny enforced
  expect_true(any(grepl("^PRE:Write", ev$log)))           # PreToolUse fired
  expect_true(any(grepl("^DENIED:Write", ev$log)))        # PermissionDenied fired
})

test_that(".tool_gate_fn allows read-only tools but still fires PreToolUse", {
  reg <- HookRegistry$new(); ev <- new.env(); ev$log <- character()
  reg$register_pre(function(tool_name, tool_input) ev$log <- c(ev$log, tool_name))
  gate <- .tool_gate_fn(list(overrides = list(), capabilities = list()),
                        function() "default", list(), NULL, reg)
  req <- ellmer::ContentToolRequest(id = "2", name = "Read",
           arguments = list(file_path = "x"))
  expect_invisible(gate(req))
  expect_true("Read" %in% ev$log)
})

test_that(".tool_gate_fn allows write tools in bypass mode", {
  gate <- .tool_gate_fn(list(overrides = list(), capabilities = list()),
                        function() "bypass", list(), NULL, NULL)
  req <- ellmer::ContentToolRequest(id = "3", name = "Write",
           arguments = list(file_path = "x", content = "y"))
  expect_invisible(gate(req))
})

test_that("capability policy 'write=ask' with no ask_fn denies write tools", {
  policy <- list(overrides = list(), capabilities = list(write = "ask"))
  gate <- .tool_gate_fn(policy, function() "bypass", list(), ask_fn = NULL, hooks = NULL)
  req <- ellmer::ContentToolRequest(id = "4", name = "Write",
           arguments = list(file_path = "x", content = "y"))
  expect_error(gate(req), class = "ellmer_tool_reject")   # ask + no ask_fn -> deny
})

test_that(".tool_gate_fn takes the async promise branch when ask_fn is async (Shiny)", {
  policy <- list(overrides = list(), capabilities = list(write = "ask"))
  gate <- .tool_gate_fn(policy, function() "bypass", list(),
                        ask_fn = function(n, i) promises::promise_resolve(TRUE),
                        hooks = NULL)
  req <- ellmer::ContentToolRequest(id = "5", name = "Write",
           arguments = list(file_path = "x", content = "y"))
  res <- gate(req)
  expect_true(promises::is.promise(res))   # async decision deferred to a promise
})
