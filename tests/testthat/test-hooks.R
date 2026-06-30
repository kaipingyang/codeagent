# tests/testthat/test-hooks.R
# Tests for HookRegistry lifecycle events (M5: 7 -> 12 events).

test_that("HookEvent exposes all 12 lifecycle events", {
  expect_length(HookEvent, 12L)
  expect_true(all(c(
    "PreToolUse", "PostToolUse", "PostToolUseFailure",
    "PermissionDenied", "PermissionRequest", "UserMessage", "AssistantMessage",
    "SessionStart", "Stop", "PreCompact", "SubagentStart", "SubagentStop"
  ) %in% unlist(HookEvent)))
})

test_that("registry initializes a bucket for every event", {
  reg <- HookRegistry$new()
  expect_equal(reg$count(), 0L)
  expect_silent(reg$run_session_start(list()))   # empty buckets no-op
  expect_silent(reg$run_stop("completed", list()))
  expect_silent(reg$run_pre_compact("auto", list()))
})

test_that("SessionStart hook fires with context", {
  reg <- HookRegistry$new()
  seen <- NULL
  reg$register(HookEvent$SESSION_START, function(ctx) seen <<- ctx)
  reg$run_session_start(list(cwd = "/x", session_id = "s1"))
  expect_identical(seen$session_id, "s1")
})

test_that("Stop hook fires with stop_reason", {
  reg <- HookRegistry$new()
  seen <- NULL
  reg$register(HookEvent$STOP, function(reason, ctx) seen <<- reason)
  reg$run_stop("max_turns", list())
  expect_identical(seen, "max_turns")
})

test_that("PreCompact hook fires with level", {
  reg <- HookRegistry$new()
  seen <- NULL
  reg$register(HookEvent$PRE_COMPACT, function(level, ctx) seen <<- level)
  reg$run_pre_compact("auto", list(tokens = 100))
  expect_identical(seen, "auto")
})

test_that("Subagent start/stop hooks fire with description + result", {
  reg <- HookRegistry$new()
  log <- list()
  reg$register(HookEvent$SUBAGENT_START, function(desc, ctx) log$start <<- desc)
  reg$register(HookEvent$SUBAGENT_STOP, function(desc, res, ctx) {
    log$stop <<- desc; log$res <<- res
  })
  reg$run_subagent_start("find bugs", list())
  reg$run_subagent_stop("find bugs", "found 3", list())
  expect_identical(log$start, "find bugs")
  expect_identical(log$res, "found 3")
})

test_that("existing PreToolUse / PostToolUse hooks still work", {
  reg <- HookRegistry$new()
  reg$register_pre(function(tool, input) list(action = "deny", message = "blocked"))
  res <- reg$run_pre("Bash", list(command = "rm -rf /"))
  expect_identical(res$action, "deny")

  reg2 <- HookRegistry$new()
  reg2$register_post(function(tool, input, output)
    list(action = "updated_output", output = "REDACTED"))
  out <- reg2$run_post("Read", list(file_path = "secret"), "raw output")
  expect_identical(out, "REDACTED")   # run_post returns the (updated) output value
})

test_that("clear() resets all 12 buckets", {
  reg <- HookRegistry$new()
  reg$register(HookEvent$SESSION_START, function(ctx) NULL)
  reg$register(HookEvent$STOP, function(r, c) NULL)
  expect_equal(reg$count(), 2L)
  reg$clear()
  expect_equal(reg$count(), 0L)
})
