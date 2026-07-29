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
