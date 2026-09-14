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
    "TaskCreate", "TaskList", "TodoWrite", "use_skill", "Agent"
  )
  missing <- setdiff(referenced, nms)
  expect_identical(missing, character(0),
    info = paste("prompt references tools not in registry:",
                 paste(missing, collapse = ", ")))
  expect_false("TeamRun" %in% nms)
  expect_match(ca$chat$get_system_prompt(),
               "Process-based team/background delegation is unavailable")
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


test_that("register_tools FALSE derives guidance from the existing registry", {
  empty_chat <- ellmer::chat_anthropic(model = "fixture")
  empty <- codeagent_client(empty_chat, cwd = tempdir(), register_tools = FALSE)
  expect_length(empty$chat$get_tools(), 0L)
  expect_match(empty$chat$get_system_prompt(), "No tools are registered")
  expect_false(grepl("Read to read|foreground Agent tool",
                     empty$chat$get_system_prompt()))

  agent_chat <- ellmer::chat_anthropic(model = "fixture")
  agent_chat$register_tool(ellmer::tool(
    function(value = "") value, name = "Agent", description = "fixture",
    arguments = list(value = ellmer::type_string("value", required = FALSE))))
  agent <- codeagent_client(agent_chat, cwd = tempdir(), register_tools = FALSE)
  expect_match(agent$chat$get_system_prompt(), "foreground Agent tool")
  expect_false(grepl("No tools are registered", agent$chat$get_system_prompt(),
                     fixed = TRUE))
})

test_that("delegation prompt is derived from final registered tool names", {
  fixture <- function(name) ellmer::tool(
    function(value = "") value,
    name = name, description = name,
    arguments = list(value = ellmer::type_string("value", required = FALSE)))
  settings <- list(model = "fixture", permission_mode = "default", max_turns = 5L,
                   foreground_delegation_available = TRUE,
                   process_delegation_available = TRUE)
  chat <- ellmer::chat_anthropic(model = "fixture")
  chat$set_system_prompt(paste0(
    .build_system_prompt(settings, tempdir()), "\n\nRUNTIME_SENTINEL"))

  chat$register_tool(fixture("Agent"))
  .sync_delegation_prompt(chat, settings, tempdir())
  expect_match(chat$get_system_prompt(), "foreground Agent tool")
  expect_match(chat$get_system_prompt(),
               "Process-based team/background delegation is unavailable")
  expect_false(grepl("TeamRun runs several", chat$get_system_prompt(), fixed = TRUE))

  chat$register_tool(fixture("TeamRun"))
  .sync_delegation_prompt(chat, settings, tempdir())
  expect_match(chat$get_system_prompt(), "TeamRun runs several")

  chat$set_tools(list(fixture("Read")))
  .sync_delegation_prompt(chat, settings, tempdir())
  expect_match(chat$get_system_prompt(), "No delegation tools are registered")

  chat$set_tools(list(fixture("TeamRun")))
  .sync_delegation_prompt(chat, settings, tempdir())
  expect_match(chat$get_system_prompt(), "TeamRun is registered")
  expect_match(chat$get_system_prompt(), "Foreground Agent delegation is unavailable")
  expect_match(chat$get_system_prompt(), "RUNTIME_SENTINEL")
  expect_match(chat$get_system_prompt(),
               "# Session\\n- Permission mode: default\\n- Max turns: 5")
  expect_false(grepl("# Sessionn-", chat$get_system_prompt(), fixed = TRUE))
})
