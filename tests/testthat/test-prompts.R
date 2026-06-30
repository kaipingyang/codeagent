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
  expect_match(p, "verify it actually works")
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

test_that(".prompt_subagent ports the DEFAULT_AGENT_PROMPT essentials", {
  sp <- codeagent:::.prompt_subagent("review the parser", "bubble", NULL)
  expect_match(sp, "concise report")
  expect_match(sp, "gold-plate")
  expect_match(sp, "review the parser")
  expect_match(sp, "bubble")
  # With a worktree path
  sp2 <- codeagent:::.prompt_subagent("x", "bubble", "/tmp/wt")
  expect_match(sp2, "/tmp/wt")
})

test_that("static prompt sections have no non-ASCII (R CMD check safe)", {
  # Only the ported guidance sections must be ASCII; runtime-injected content
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
