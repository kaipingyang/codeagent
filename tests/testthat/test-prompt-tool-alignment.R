# Regression for 15B: every tool the system prompt tells the model to use must
# exist under that exact name in the registered tool set, and no tool may fall
# back to ellmer's anonymous "tool_00N" name.

test_that("prompt-referenced tool names all exist in the registered tools", {
  skip_if_not_installed("btw")
  skip_if_not_installed("ellmer")

  # A chat that constructs offline (fake endpoint; we never call the LLM).
  client <- ellmer::chat_openai(base_url = "http://127.0.0.1:1/v1", model = "gpt-4o-mini")
  ca <- suppressWarnings(suppressMessages(
    codeagent_client(chat = client, cwd = getwd())
  ))
  nms <- vapply(ca$chat$get_tools(), function(t) t@name, character(1))

  # Names the system prompt (prompts.R) instructs the model to call by name.
  referenced <- c(
    "Bash", "Read", "Write", "Edit", "MultiEdit", "Glob", "Grep", "LS",
    "TaskCreate", "TaskList", "TodoWrite", "TeamRun", "use_skill",
    "btw_tool_agent_subagent"
  )
  missing <- setdiff(referenced, nms)
  expect_identical(missing, character(0),
    info = paste("prompt references tools not in registry:",
                 paste(missing, collapse = ", ")))
})

test_that("no registered tool uses ellmer's anonymous tool_NNN fallback name", {
  skip_if_not_installed("btw")
  skip_if_not_installed("ellmer")

  client <- ellmer::chat_openai(base_url = "http://127.0.0.1:1/v1", model = "gpt-4o-mini")
  ca <- suppressWarnings(suppressMessages(
    codeagent_client(chat = client, cwd = getwd())
  ))
  nms <- unname(vapply(ca$chat$get_tools(), function(t) t@name, character(1)))
  anon <- grep("^tool_[0-9]+$", nms, value = TRUE)
  expect_identical(anon, character(0),
    info = paste("tools missing an explicit name= (auto-named):",
                 paste(anon, collapse = ", ")))
})
