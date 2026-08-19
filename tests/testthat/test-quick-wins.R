# Tests for task 02 ellmer quick wins: finish_reason (2A) + truncation
# classification (2B).

test_that(".last_finish_reason reads the last turn's finish_reason", {
  # Stub a chat exposing last_turn() with an S3 object carrying @finish_reason.
  mk_chat <- function(fr) {
    turn <- structure(list(), class = "faketurn")
    list(last_turn = function() {
      # emulate S7 @finish_reason via an attribute-backed accessor
      structure(fr, class = "frobj")
    })
  }
  # Use a real ellmer turn to exercise the @finish_reason path.
  chat <- list(last_turn = function() ellmer::Turn("assistant", "hi"))
  # A fresh Turn has NA/empty finish_reason -> NA_character_.
  expect_true(is.na(.last_finish_reason(chat)))
  # No last_turn method -> NA.
  expect_true(is.na(.last_finish_reason(list())))
  expect_true(is.na(.last_finish_reason(NULL)))
})

test_that(".ERR_TRUNCATED matches truncation/filter signals", {
  expect_true(grepl(.ERR_TRUNCATED, "response was truncated", ignore.case = TRUE))
  expect_true(grepl(.ERR_TRUNCATED, "stopped due to max_tokens", ignore.case = TRUE))
  expect_true(grepl(.ERR_TRUNCATED, "content filter triggered", ignore.case = TRUE))
  expect_true(grepl(.ERR_TRUNCATED, "incomplete output", ignore.case = TRUE))
  expect_false(grepl(.ERR_TRUNCATED, "connection timeout", ignore.case = TRUE))
})

test_that(".handle_agent_error retries once on a truncation error", {
  calls <- 0L
  fake_chat <- list(chat = function(input) { calls <<- calls + 1L; "recovered" })
  cc  <- CompactionController$new()
  err <- simpleError("The response was truncated (max_tokens reached)")
  out <- .handle_agent_error(err, fake_chat, "hi", cc)
  expect_identical(out, "recovered")
  expect_identical(calls, 1L)   # exactly one retry
})


test_that("agent_loop maps final reason before visible hooks", {
  assistant_seen <- NULL
  stop_seen <- NULL
  hooks <- list(
    run_session_start = function(...) NULL,
    run_user_prompt_submit = function(...) list(action = "allow"),
    run_pre_compact = function(...) NULL,
    run_assistant_message = function(message) assistant_seen <<- message,
    run_stop = function(reason, context) stop_seen <<- list(reason, context))
  chat <- list(
    get_turns = function(...) list(),
    get_tokens = function(...) data.frame(),
    get_cost = function(...) NA_real_,
    chat = function(...) "partial answer",
    last_turn = function(...) ellmer::AssistantTurn(
      contents = list(ellmer::ContentText("partial answer")),
      finish_reason = "context_window"))
  ctrl <- list(maybe_compact = function(...) FALSE)
  budget <- list(should_stop = function(...) FALSE)
  resources <- list(maybe_replace = function(...) NULL)
  settings <- list(cwd = getwd(), max_turns = 10L, model_limit = 1000L,
                   model = "fake", verify_fn = NULL, hooks_registry = hooks)

  out <- agent_loop("question", chat, settings = settings,
                    compaction_ctrl = ctrl, budget_tracker = budget,
                    resource_state = resources, hooks = hooks)

  expect_identical(out$stop_reason, "truncated")
  expect_identical(out$finish_reason, "context_window")
  expect_match(out$response, "truncated", ignore.case = TRUE)
  expect_identical(assistant_seen, out$response)
  expect_identical(stop_seen[[1L]], "truncated")
  expect_identical(stop_seen[[2L]]$finish_reason, "context_window")
})


test_that("Shiny finalizer maps reason before output gate", {
  shield <- DataShield$new(strategies = list(shield_egress(max_rows = 0L)))
  df <- data.frame(id = sprintf("SHINYID%03d", 1:20), stringsAsFactors = FALSE)
  shield$register_data(df, "protected", cols = "id")
  chat <- structure(list(
    last_turn = function(...) ellmer::AssistantTurn(
      contents = list(ellmer::ContentText("result SHINYID001")),
      finish_reason = "content_filter")
  ), class = "Chat")
  attr(chat, "codeagent_data_shield") <- shield

  out <- .finalize_server_reply(
    chat, list(data_shield_engine = shield,
               data_shield_response_on_fail = "redact"))

  expect_identical(out$finish$stop_reason, "filtered")
  expect_identical(out$finish$finish_reason, "content_filter")
  expect_false(grepl("SHINYID001", out$text, fixed = TRUE))
  expect_match(out$text, "filtered", ignore.case = TRUE)
})
