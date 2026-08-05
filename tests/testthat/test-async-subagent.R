# Async / concurrent sub-agents (plan 27, Phase A).
# Unit-level only (no live LLM). The concurrent end-to-end behaviour is verified
# manually against a real model; here we test the async-turn gate and that the
# opt-in flag selects codeagent's own (promise-capable) Agent tool.

test_that(".in_async_turn() gate toggles and nests", {
  expect_false(codeagent:::.in_async_turn())
  codeagent:::.enter_async_turn()
  expect_true(codeagent:::.in_async_turn())
  codeagent:::.exit_async_turn()
  expect_false(codeagent:::.in_async_turn())

  # nested enters require matching exits
  codeagent:::.enter_async_turn()
  codeagent:::.enter_async_turn()
  expect_true(codeagent:::.in_async_turn())
  codeagent:::.exit_async_turn()
  expect_true(codeagent:::.in_async_turn())
  codeagent:::.exit_async_turn()
  expect_false(codeagent:::.in_async_turn())

  # unbalanced exit never goes negative
  codeagent:::.exit_async_turn()
  expect_false(codeagent:::.in_async_turn())
})

test_that("agent_tool(async = TRUE) uses codeagent's own Agent tool", {
  t <- agent_tool(async = TRUE)
  expect_s3_class(t, "ellmer::ToolDef")
  expect_identical(t@name, "Agent")
})

test_that("register_agent_tool accepts the async flag", {
  expect_true("async" %in% names(formals(register_agent_tool)))
  expect_true("async" %in% names(formals(agent_tool)))
})


test_that("Agent sub-chat inherits DataShield before its first tool loop", {
  shield <- DataShield$new(strategies=list(shield_describe(), shield_egress(max_rows=0)))
  shield$register_data(
    data.frame(subject_id=paste0("CHILD",sprintf("%03d",1:20))),
    name="study")
  sub_chat <- ellmer::chat_openai_compatible(
    base_url="http://x", model="m", credentials=function() "k")
  observed <- NULL

  testthat::local_mocked_bindings(
    .make_chat = function(...) sub_chat,
    register_builtin_tools = function(chat, ...) {
      chat$register_tool(ellmer::tool(
        function() "selected CHILD007", name="LeakChild",
        description="d", arguments=list()))
      invisible(chat)
    },
    .run_subagent_loop = function(sub_chat, ...) {
      tools <- sub_chat$get_tools()
      leak <- Filter(function(tool)
        identical(tryCatch(S7::prop(tool,"name"),error=function(e)""), "LeakChild"),
        tools)[[1L]]
      observed <<- leak()
      "child done"
    },
    .package = "codeagent")

  tool <- agent_tool(data_shield=shield)
  result <- tool(description="test", prompt="do it")
  expect_match(observed, "withheld|blocked")
  expect_false(grepl("CHILD007", observed, fixed=TRUE))
  expect_identical(result, "child done")
  names_now <- vapply(sub_chat$get_tools(), function(tool)
    tryCatch(S7::prop(tool,"name"),error=function(e)""), character(1))
  expect_true("DescribeData" %in% names_now)
})

test_that("DataShield forces codeagent Agent path and is accepted by registration", {
  shield <- DataShield$new()
  tool <- agent_tool(data_shield=shield)
  expect_identical(S7::prop(tool, "name"), "Agent")
  expect_true("data_shield" %in% names(formals(agent_tool)))
  expect_true("data_shield" %in% names(formals(register_agent_tool)))
})


test_that("async Agent uses the same shielded sub-chat setup", {
  shield <- DataShield$new()
  sub_chat <- ellmer::chat_openai_compatible(
    base_url="http://x", model="m", credentials=function() "k")
  testthat::local_mocked_bindings(
    .make_chat = function(...) sub_chat,
    register_builtin_tools = function(chat, ...) {
      chat$register_tool(ellmer::tool(function() mtcars, name="DumpChild",
                                      description="d", arguments=list()))
      invisible(chat)
    },
    .run_subagent_loop_async = function(...) promises::promise_resolve("done"),
    .package = "codeagent")
  codeagent:::.enter_async_turn()
  on.exit(codeagent:::.exit_async_turn(), add=TRUE)
  promise <- agent_tool(async=TRUE, data_shield=shield)(
    description="async", prompt="do it")
  expect_true(inherits(promise, "promise"))
  names_now <- vapply(sub_chat$get_tools(), function(tool)
    tryCatch(S7::prop(tool,"name"),error=function(e)""), character(1))
  expect_true("DescribeData" %in% names_now)
  dump <- sub_chat$get_tools()[[which(names_now == "DumpChild")]]
  expect_match(dump(), "tabular output withheld")
})
