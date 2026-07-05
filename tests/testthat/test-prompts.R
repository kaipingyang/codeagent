# tests/testthat/test-prompts.R
# Tests for the ported Claude Code system prompt sections.

.mk_settings <- function(...) {
  s <- list(model = "test-model", permission_mode = "default", max_turns = 100L)
  utils::modifyList(s, list(...))
}

test_that("each prompt section returns a non-empty string", {
  s <- .mk_settings()
  expect_true(nzchar(codeagent:::.prompt_identity(s)))
  expect_true(nzchar(codeagent:::.prompt_tone_and_style(s)))
  expect_true(nzchar(codeagent:::.prompt_doing_tasks()))
  expect_true(nzchar(codeagent:::.prompt_code_conventions()))
  expect_true(nzchar(codeagent:::.prompt_using_tools(s)))
  expect_true(nzchar(codeagent:::.prompt_actions()))
  expect_true(nzchar(codeagent:::.prompt_r_specifics()))
})

test_that(".build_system_prompt contains key behavioural anchors", {
  s <- .mk_settings()
  p <- codeagent:::.build_system_prompt(s, getwd())
  expect_match(p, "# Tone and style")
  expect_match(p, "# Doing tasks")
  expect_match(p, "# Following conventions")
  expect_match(p, "# Using your tools")
  expect_match(p, "# R-specific guidance")
  expect_match(p, "Confirm a task works before calling it complete")
  expect_match(p, "tidyverse")
  expect_match(p, "renv")
  expect_match(p, "file_path:line_number")
})

test_that(".build_system_prompt injects CLAUDE.md when present", {
  s <- .mk_settings(claude_md = "PROJECT_SPECIFIC_RULE_XYZ")
  p <- codeagent:::.build_system_prompt(s, getwd())
  expect_match(p, "PROJECT_SPECIFIC_RULE_XYZ")
  expect_match(p, "Project Instructions")
})

test_that(".build_system_prompt is stable (no Sys.time/date -> cache-safe)", {
  s <- .mk_settings()
  p1 <- codeagent:::.build_system_prompt(s, getwd())
  p2 <- codeagent:::.build_system_prompt(s, getwd())
  expect_identical(p1, p2)
  # Must NOT embed a date/time (that belongs in .build_system_reminder)
  expect_false(grepl("\\d{4}-\\d{2}-\\d{2}", p1))
})

test_that(".prompt_subagent produces the sub-agent essentials", {
  sp <- codeagent:::.prompt_subagent("review the parser", "bubble", NULL)
  expect_match(sp, "short report")
  expect_match(sp, "padding it out")
  expect_match(sp, "review the parser")
  expect_match(sp, "bubble")
  # With a worktree path
  sp2 <- codeagent:::.prompt_subagent("x", "bubble", "/tmp/wt")
  expect_match(sp2, "/tmp/wt")
})

test_that("static prompt sections have no non-ASCII (R CMD check safe)", {
  # Only the static guidance sections must be ASCII; runtime-injected content
  # (CLAUDE.md, skill descriptions) may legitimately contain non-ASCII.
  s <- .mk_settings()
  static <- paste(
    codeagent:::.prompt_identity(s),
    codeagent:::.prompt_tone_and_style(s),
    codeagent:::.prompt_doing_tasks(),
    codeagent:::.prompt_code_conventions(),
    codeagent:::.prompt_using_tools(s),
    codeagent:::.prompt_actions(),
    codeagent:::.prompt_r_specifics(),
    codeagent:::.prompt_subagent("x", "bubble", NULL)
  )
  expect_false(any(utf8ToInt(static) > 127L))
})

test_that("system prompt stays within a reasonable token budget", {
  s <- .mk_settings()
  p <- codeagent:::.build_system_prompt(s, getwd())
  # Rough char/4 token estimate; the guidance should be well under ~4k tokens.
  est_tokens <- nchar(p) / 4
  expect_lt(est_tokens, 4000)
})

# ---------------------------------------------------------------------------
# P3 gap-fill: actions / identity interpolation / context_blocks
# ---------------------------------------------------------------------------

test_that(".prompt_actions covers reversibility and risky-ops guidance", {
  a <- codeagent:::.prompt_actions()
  expect_match(a, "# Executing actions with care")
  expect_match(a, "how reversible an action is")
  expect_match(a, "rm -rf")
  expect_match(a, "force-push")
})

test_that(".prompt_identity interpolates cwd and model", {
  s <- .mk_settings(model = "MODEL_ABC")
  id <- codeagent:::.prompt_identity(s, "/some/work/dir")
  expect_match(id, "/some/work/dir")
  expect_match(id, "MODEL_ABC")
})

test_that(".prompt_context_blocks injects CLAUDE.md + permission mode", {
  s <- .mk_settings(claude_md = "CTX_RULE_123", permission_mode = "plan",
                    max_turns = 7L)
  cb <- codeagent:::.prompt_context_blocks(s, getwd())
  expect_match(cb, "CTX_RULE_123")
  expect_match(cb, "Permission mode: plan")
  expect_match(cb, "Max turns: 7")
})

test_that(".prompt_context_blocks omits CLAUDE.md section when absent", {
  s <- .mk_settings()  # no claude_md
  cb <- codeagent:::.prompt_context_blocks(s, tempdir())
  expect_false(grepl("Project Instructions", cb))
  expect_match(cb, "Permission mode")
})


# ---------------------------------------------------------------------------
# .strip_system_reminder: ephemeral <system-reminder> blocks must never leak
# into user-facing text (session titles, restored chat bubbles).
# ---------------------------------------------------------------------------

test_that(".strip_system_reminder removes reminder blocks but keeps user text", {
  x <- "hello\n\n<system-reminder>\nCurrent date/time: 2026-07-01\nAgent loop iteration: 1\n</system-reminder>"
  expect_equal(codeagent:::.strip_system_reminder(x), "hello")
})

test_that(".strip_system_reminder is a no-op when there is no reminder", {
  expect_equal(codeagent:::.strip_system_reminder("just a message"), "just a message")
})

test_that(".strip_system_reminder passes non-character through untouched", {
  expect_equal(codeagent:::.strip_system_reminder(list(1, 2)), list(1, 2))
  expect_null(codeagent:::.strip_system_reminder(NULL))
})

test_that(".strip_system_reminder handles a reminder-only string", {
  x <- "<system-reminder>ephemeral</system-reminder>"
  expect_equal(codeagent:::.strip_system_reminder(x), "")
})
