# Background (non-blocking) sub-agents (plan 27, Phase B).
# Unit-level (no live LLM). Real spawn -> codeagent sub-agent is verified
# manually against a model; here we test the registry, poll, and reminder wiring.
#
# NB: .bg_state is a package-internal environment. Mutate it via a captured
# reference (st$agents <- ...); `codeagent:::.bg_state$agents <- ...` fails
# because R rewrites it as an assignment to the locked ::: binding.

st <- codeagent:::.bg_state

test_that("bg_take_completed returns completed once, then marks retrieved", {
  st$agents <- list(
    "1" = list(id = "1", prompt = "p", status = "done",
               result = "R", retrieved = FALSE))
  got <- codeagent:::.bg_take_completed()
  expect_length(got, 1L)
  expect_identical(got[[1L]]$result, "R")
  expect_length(codeagent:::.bg_take_completed(), 0L)  # now retrieved
  st$agents <- list()
})

test_that("bg reminder block reports completed results and running agents", {
  st$agents <- list(
    "1" = list(id = "1", prompt = "explore data", status = "done",
               result = "found 3 trends", retrieved = FALSE),
    "2" = list(id = "2", prompt = "long task", status = "running"))
  blk <- codeagent:::.bg_reminder_block()
  expect_true(grepl("found 3 trends", blk, fixed = TRUE))
  expect_true(grepl("still running", blk))
  expect_true(grepl("#2", blk, fixed = TRUE))
  st$agents <- list()
})

test_that("system reminder surfaces a completed background result", {
  st$agents <- list(
    "1" = list(id = "1", prompt = "q", status = "done",
               result = "BG_DONE_XYZ", retrieved = FALSE))
  rem <- codeagent:::.build_system_reminder(list(), iteration = 2L,
                                            cwd = tempdir())
  expect_true(grepl("BG_DONE_XYZ", rem, fixed = TRUE))
  st$agents <- list()
})

test_that("BackgroundAgent tool builds with the expected name", {
  t <- codeagent:::background_agent_tool()
  expect_s3_class(t, "ellmer::ToolDef")
  expect_identical(t@name, "BackgroundAgent")
})

test_that("bg_poll resolves a real mirai task (fire-and-forget)", {
  skip_if_not_installed("mirai")
  codeagent:::.bg_ensure_daemons(1L)
  m <- mirai::mirai({ paste("answer", 42) }, .compute = codeagent:::.BG_COMPUTE)
  st$agents <- list(
    "9" = list(id = "9", prompt = "x", status = "running",
               result = NULL, retrieved = FALSE, mirai = m))
  for (i in 1:80) {
    codeagent:::.bg_poll()
    if (identical(st$agents[["9"]]$status, "done")) break
    Sys.sleep(0.1)
  }
  expect_identical(st$agents[["9"]]$status, "done")
  expect_identical(st$agents[["9"]]$result, "answer 42")
  codeagent:::.bg_shutdown()
})

# --- /bg and /bgstatus user slash commands ---

test_that("/bg and /bgstatus are registered in both command lists", {
  expect_true(all(c("bg", "bgstatus") %in% codeagent:::.LOCAL_COMMANDS))
  expect_true(all(c("bg", "bgstatus") %in% codeagent:::.REPL_META_CMDS))
})

test_that(".repl_dispatch parses /bg and /bgstatus", {
  expect_identical(codeagent:::.repl_dispatch("/bg do a thing"),
                   list(action = "bg", arg = "do a thing"))
  expect_identical(codeagent:::.repl_dispatch("/bgstatus")$action, "bgstatus")
})

test_that(".preprocess_input treats /bg as a local command (not sent to LLM)", {
  p <- codeagent:::.preprocess_input("/bg do X")
  expect_identical(p$type, "command")
  expect_identical(p$name, "bg")
})

test_that("bg slash helpers handle empty / no-agent cases", {
  st <- codeagent:::.bg_state
  st$agents <- list()
  expect_match(codeagent:::.bg_slash_spawn(""), "Usage")
  expect_identical(codeagent:::.bg_status_text(), "No background sub-agents.")
})

test_that(".chat_command_result routes /bgstatus to an append action", {
  st <- codeagent:::.bg_state
  st$agents <- list()
  r <- codeagent:::.chat_command_result("bgstatus")
  expect_identical(r$action, "append")
  expect_match(r$feedback, "No background sub-agents")
})


test_that("BackgroundAgent fails closed while DataShield is active", {
  shield <- DataShield$new()
  st <- codeagent:::.bg_state
  before <- st$counter
  tool <- codeagent:::background_agent_tool(shield)
  result <- tool(prompt="read protected data")
  expect_match(result, "disabled while Data Shield is active")
  expect_identical(st$counter, before) # never spawned a mirai task
})

test_that("/bg fails closed while DataShield is active", {
  shield <- DataShield$new()
  result <- codeagent:::.bg_slash_spawn("read protected data", shield)
  expect_match(result, "disabled while Data Shield is active")
  decision <- codeagent:::.chat_command_result(
    "bg", "read protected data", data_shield=shield)
  expect_match(decision$feedback, "disabled while Data Shield is active")
})
