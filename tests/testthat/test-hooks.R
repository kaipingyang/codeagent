# tests/testthat/test-hooks.R
# Tests for HookRegistry lifecycle events.
# M5: 7 -> 12 events. 2026-08: 12 -> 28 (27 CC-parity events + codeagent-only
# AssistantMessage). A group fires live; B group is Shiny-only; C group defined
# for a complete allowlist but has no live trigger.

test_that("HookEvent exposes the original 12 lifecycle events", {
  expect_true(all(c(
    "PreToolUse", "PostToolUse", "PostToolUseFailure",
    "PermissionDenied", "PermissionRequest", "UserMessage", "AssistantMessage",
    "SessionStart", "Stop", "PreCompact", "SubagentStart", "SubagentStop"
  ) %in% unlist(HookEvent)))
})

test_that("HookEvent covers all 27 Claude Code events + AssistantMessage", {
  cc_events <- c(
    "PreToolUse", "PostToolUse", "PostToolUseFailure", "Notification",
    "UserMessage",  # = CC UserPromptSubmit (renamed)
    "SessionStart", "SessionEnd", "Stop", "StopFailure", "SubagentStart",
    "SubagentStop", "PreCompact", "PostCompact", "PermissionRequest",
    "PermissionDenied", "Setup", "TeammateIdle", "TaskCreated", "TaskCompleted",
    "Elicitation", "ElicitationResult", "ConfigChange", "WorktreeCreate",
    "WorktreeRemove", "InstructionsLoaded", "CwdChanged", "FileChanged")
  expect_true(all(cc_events %in% unlist(HookEvent)))
  # AssistantMessage is codeagent-only (CC has no such event) -> 27 + 1 = 28.
  expect_length(HookEvent, 28L)
  expect_true("AssistantMessage" %in% unlist(HookEvent))
})

test_that("A-group events fire with their payloads", {
  reg <- HookRegistry$new()
  seen <- list()
  reg$register(HookEvent$SESSION_END,        function(reason, ctx) seen$se   <<- reason)
  reg$register(HookEvent$POST_COMPACT,       function(trig, sum, ctx) seen$pc <<- trig)
  reg$register(HookEvent$STOP_FAILURE,       function(err, ctx) seen$sf       <<- err)
  reg$register(HookEvent$NOTIFICATION,       function(msg, type, ctx) seen$nt <<- type)
  reg$register(HookEvent$TASK_CREATED,       function(id, subj, ctx) seen$tc  <<- id)
  reg$register(HookEvent$TASK_COMPLETED,     function(id, subj, ctx) seen$td  <<- subj)
  reg$register(HookEvent$WORKTREE_CREATE,    function(name, ctx) seen$wc      <<- name)
  reg$register(HookEvent$WORKTREE_REMOVE,    function(path, ctx) seen$wr      <<- path)
  reg$register(HookEvent$INSTRUCTIONS_LOADED,function(fp, mt, lr, ctx) seen$il <<- mt)

  reg$run_session_end("prompt_input_exit", list())
  reg$run_post_compact("auto", "summary text", list())
  reg$run_stop_failure("boom", list())
  reg$run_notification("hi", "error", list())
  reg$run_task_created("7", "write tests", list())
  reg$run_task_completed("7", "write tests", list())
  reg$run_worktree_create("wt-1", list())
  reg$run_worktree_remove("/tmp/wt-1", list())
  reg$run_instructions_loaded("/x/CLAUDE.md", "Project", "session_start", list())

  expect_identical(seen$se, "prompt_input_exit")
  expect_identical(seen$pc, "auto")
  expect_identical(seen$sf, "boom")
  expect_identical(seen$nt, "error")
  expect_identical(seen$tc, "7")
  expect_identical(seen$td, "write tests")
  expect_identical(seen$wc, "wt-1")
  expect_identical(seen$wr, "/tmp/wt-1")
  expect_identical(seen$il, "Project")
})

test_that("B-group (FileChanged / ConfigChange) fire methods exist and dispatch", {
  reg <- HookRegistry$new()
  seen <- list()
  reg$register(HookEvent$FILE_CHANGED,  function(fp, evt, ctx) seen$fc <<- evt)
  reg$register(HookEvent$CONFIG_CHANGE, function(src, fp, ctx) seen$cc <<- src)
  reg$run_file_changed("/x/a.R", "change", list())
  reg$run_config_change("user_settings", "/x/settings.json", list())
  expect_identical(seen$fc, "change")
  expect_identical(seen$cc, "user_settings")
})

test_that("C-group events are defined but have no run_* fire method", {
  # These exist in the allowlist for parity but never fire (no trigger).
  c_group <- c("Elicitation", "ElicitationResult", "TeammateIdle", "Setup", "CwdChanged")
  expect_true(all(c_group %in% unlist(HookEvent)))
  reg <- HookRegistry$new()
  # No run_elicitation / run_teammate_idle / run_setup / run_cwd_changed methods.
  expect_false("run_elicitation"    %in% ls(reg))
  expect_false("run_teammate_idle"  %in% ls(reg))
  expect_false("run_setup"          %in% ls(reg))
  expect_false("run_cwd_changed"    %in% ls(reg))
})

test_that("AssistantMessage remains notify-only (not upgraded to deny/redact)", {
  reg <- HookRegistry$new()
  seen <- NULL
  reg$register(HookEvent$ASSISTANT_MESSAGE, function(msg) seen <<- msg)
  # Even if a hook returns a deny-like list, run_assistant_message ignores it.
  reg$register(HookEvent$ASSISTANT_MESSAGE, function(msg) list(action = "deny"))
  out <- reg$run_assistant_message("model text")
  expect_identical(seen, "model text")
  expect_null(out)   # invisible(NULL): notify-only, no interception contract
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

test_that("clear() resets all buckets", {
  reg <- HookRegistry$new()
  reg$register(HookEvent$SESSION_START, function(ctx) NULL)
  reg$register(HookEvent$STOP, function(r, c) NULL)
  expect_equal(reg$count(), 2L)
  reg$clear()
  expect_equal(reg$count(), 0L)
})

test_that("TaskCreate/TaskUpdate tools fire TaskCreated/TaskCompleted via closures", {
  reg <- HookRegistry$new()
  fired <- list()
  reg$register(HookEvent$TASK_CREATED,   function(id, subj, ctx) fired$created   <<- subj)
  reg$register(HookEvent$TASK_COMPLETED, function(id, subj, ctx) fired$completed <<- subj)

  store <- codeagent:::.new_task_store()
  create <- codeagent:::task_create_tool(store, reg)
  update <- codeagent:::task_update_tool(store, reg)
  run <- function(tool, ...) tool(...)   # ellmer ToolDef is directly callable

  run(create, subject = "write tests", description = "cover hooks")
  expect_identical(fired$created, "write tests")
  expect_null(fired$completed)                       # not completed yet

  run(update, task_id = "1", status = "in_progress") # no completion fire
  expect_null(fired$completed)
  run(update, task_id = "1", status = "completed")   # fires once
  expect_identical(fired$completed, "write tests")

  # Re-updating an already-completed task must NOT fire again.
  fired$completed <- NULL
  run(update, task_id = "1", status = "completed", subject = "write tests")
  expect_null(fired$completed)
})

test_that(".load_claude_md records contributing files for InstructionsLoaded replay", {
  tmp <- withr::local_tempdir()
  writeLines(c("# Project rules", "Be terse."), file.path(tmp, "CLAUDE.md"))
  writeLines(character(0), file.path(tmp, "AGENTS.md"))   # empty -> must NOT be recorded
  out <- codeagent:::.load_claude_md(tmp)
  loaded <- attr(out, "loaded_files")
  expect_true(is.character(loaded) && length(loaded) >= 1L)
  # The non-empty CLAUDE.md contributed; the empty AGENTS.md did not.
  expect_true(any(grepl("CLAUDE\\.md$", loaded)))
  expect_false(any(grepl("AGENTS\\.md$", loaded)))
})
