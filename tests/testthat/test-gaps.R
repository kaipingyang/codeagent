# tests/testthat/test-gaps.R
# Tests for the four P1 gap closures: subagent bubble, session rewind,
# thinking visibility, plan-mode tools.

library(ellmer)

# ---------------------------------------------------------------------------
# Gap 1: Session rewind -- truncate_chat_turns
# ---------------------------------------------------------------------------

.mk_chat_with_turns <- function(n_turns) {
  ch <- chat_anthropic(model = "claude-sonnet-4-6")
  turns <- list()
  for (i in seq_len(n_turns)) {
    role <- if (i %% 2 == 1) "user" else "assistant"
    turns <- c(turns, list(Turn(role, paste0("msg", i))))
  }
  ch$set_turns(turns)
  ch
}

test_that("truncate_chat_turns keeps the first N turns", {
  ch <- .mk_chat_with_turns(6L)
  kept <- truncate_chat_turns(ch, 4L)
  expect_equal(kept, 4L)
  expect_equal(length(ch$get_turns()), 4L)
})

test_that("truncate_chat_turns is a no-op when keep >= current", {
  ch <- .mk_chat_with_turns(4L)
  kept <- truncate_chat_turns(ch, 10L)
  expect_equal(kept, 4L)
  expect_equal(length(ch$get_turns()), 4L)
})

test_that("truncate_chat_turns to 0 clears all turns", {
  ch <- .mk_chat_with_turns(4L)
  kept <- truncate_chat_turns(ch, 0L)
  expect_equal(kept, 0L)
  expect_equal(length(ch$get_turns()), 0L)
})

test_that("truncate_chat_turns handles empty chat", {
  ch <- chat_anthropic(model = "claude-sonnet-4-6")
  expect_equal(truncate_chat_turns(ch, 2L), 0L)
})

test_that("/rewind dispatches with arg", {
  d <- codeagent:::.repl_dispatch("/rewind 2")
  expect_identical(d$action, "rewind")
  expect_identical(d$arg, "2")
  d0 <- codeagent:::.repl_dispatch("/rewind")
  expect_identical(d0$action, "rewind")
})

# ---------------------------------------------------------------------------
# Gap 2: Plan-mode tools + mode_env live checker
# ---------------------------------------------------------------------------

test_that(".make_permission_checker reads live mode from an environment", {
  mode_env <- new.env(parent = emptyenv())
  mode_env$mode <- "bypass"
  checker <- codeagent:::.make_permission_checker("Write", mode_env, list(), NULL)
  expect_true(checker(list(file_path = "x.R")))   # bypass -> allow

  mode_env$mode <- "plan"
  expect_false(checker(list(file_path = "x.R")))  # plan -> deny (non-readonly)
})

test_that(".make_permission_checker still accepts a static mode string", {
  checker <- codeagent:::.make_permission_checker("Read", "default", list(), NULL)
  expect_true(checker(list(file_path = "x.R")))   # Read is read-only -> allow
})

test_that("enter/exit_plan_mode tools flip mode_env$mode", {
  mode_env <- new.env(parent = emptyenv())
  mode_env$mode <- "default"

  enter <- codeagent:::enter_plan_mode_tool(mode_env)
  exit  <- codeagent:::exit_plan_mode_tool(mode_env)

  # ellmer ToolDef objects are callable directly.
  res_in <- enter(reason = "thinking")
  expect_identical(mode_env$mode, "plan")
  expect_true(S7::S7_inherits(res_in, ellmer::ContentToolResult))

  res_out <- exit()
  expect_identical(mode_env$mode, "default")
  expect_true(S7::S7_inherits(res_out, ellmer::ContentToolResult))
})

test_that("exit_plan_mode never restores into 'plan'", {
  mode_env <- new.env(parent = emptyenv())
  mode_env$mode <- "plan"
  mode_env$prev <- "plan"            # pathological
  exit <- codeagent:::exit_plan_mode_tool(mode_env)
  exit()
  expect_identical(mode_env$mode, "default")
})

test_that("plan mode blocks writes but allows reads via the same checker", {
  mode_env <- new.env(parent = emptyenv())
  mode_env$mode <- "default"
  write_chk <- codeagent:::.make_permission_checker("Write", mode_env, list(), NULL)
  read_chk  <- codeagent:::.make_permission_checker("Read",  mode_env, list(), NULL)

  codeagent:::enter_plan_mode_tool(mode_env)()
  expect_false(write_chk(list(file_path = "a.R")))
  expect_true(read_chk(list(file_path = "a.R")))
})

# ---------------------------------------------------------------------------
# Gap 3: Thinking visibility helpers
# ---------------------------------------------------------------------------

test_that(".chunk_text extracts text from ContentText and strings", {
  expect_equal(codeagent:::.chunk_text("plain"), "plain")
  ct <- ellmer::ContentText("hello")
  expect_equal(codeagent:::.chunk_text(ct), "hello")
})

test_that(".fmt_thinking wraps non-empty text in ANSI dim and is empty otherwise", {
  out <- codeagent:::.fmt_thinking("reasoning")
  expect_true(grepl("reasoning", out))
  expect_true(grepl("\033\\[2m", out))
  expect_equal(codeagent:::.fmt_thinking(""), "")
  expect_equal(codeagent:::.fmt_thinking(NULL), "")
})

# ---------------------------------------------------------------------------
# Gap 4: Subagent bubble + ask_fn passthrough
# ---------------------------------------------------------------------------

test_that("agent_tool accepts an ask_fn argument", {
  expect_true("ask_fn" %in% names(formals(codeagent:::agent_tool)))
  expect_true("ask_fn" %in% names(formals(register_agent_tool)))
})

test_that("bubble mode resolves to 'ask' so it can bubble to the parent", {
  expect_equal(check_permission("Write", "bubble"), "ask")
  expect_equal(check_permission("Bash",  "bubble"), "ask")
  # Read-only still allowed in bubble
  expect_equal(check_permission("Read",  "bubble"), "ask")
})
