# tests/testthat/test-model_switch.R
# Unit tests for lossless mid-conversation model switching (harness layer).

library(ellmer)

.mk_client <- function(turns = NULL) {
  ch <- chat_anthropic(model = "claude-sonnet-4-6")
  if (!is.null(turns)) ch$set_turns(turns)
  codeagent_client(ch, permission_mode = "bypass", btw_groups = NULL, cwd = getwd())
}

# ---------------------------------------------------------------------------
# Route A: in-place provider swap
# ---------------------------------------------------------------------------

test_that("switch_model Route A keeps the same Chat object + history", {
  cli <- .mk_client(list(Turn("user", "q1"), Turn("assistant", "a1")))
  old_chat <- cli$chat
  n_tools  <- length(cli$chat$get_tools())

  cli2 <- switch_model(cli, "anthropic/claude-haiku-4-5")

  expect_identical(cli2$chat, old_chat)                       # same object (Route A)
  expect_identical(cli2$settings$model, "claude-haiku-4-5")
  expect_identical(cli2$chat$get_model(), "claude-haiku-4-5")
  expect_length(cli2$chat$get_turns(), 2L)                    # history preserved
  expect_equal(length(cli2$chat$get_tools()), n_tools)        # tools preserved
  expect_false(is.null(cli2$chat$get_system_prompt()))        # sp preserved
})

test_that("switch_model preserves tool-call turns across the swap", {
  req <- ContentToolRequest(id = "c1", name = "weather",
                            arguments = list(city = "NYC"))
  res <- ContentToolResult(value = "sunny", request = req)
  cli <- .mk_client(list(
    Turn("user", "weather?"),
    Turn("assistant", contents = list(req)),
    Turn("user", contents = list(res))
  ))

  cli2 <- switch_model(cli, "anthropic/claude-haiku-4-5")
  t <- cli2$chat$get_turns()
  expect_length(t, 3L)
  expect_identical(t[[2]]@contents[[1]]@name, "weather")
  expect_identical(t[[3]]@contents[[1]]@request@id, "c1")
})

# ---------------------------------------------------------------------------
# Route B: fallback rebuild (force by stubbing .swap_provider to fail)
# ---------------------------------------------------------------------------

test_that("switch_model Route B rebuilds client when in-place swap fails", {
  cli <- .mk_client(list(Turn("user", "q1"), Turn("assistant", "a1")))
  old_chat <- cli$chat

  # Force Route B by making the provider swap fail.
  testthat::local_mocked_bindings(
    .swap_provider = function(chat, new_chat) FALSE,
    .package = "codeagent"
  )
  cli2 <- switch_model(cli, "anthropic/claude-haiku-4-5")

  expect_false(identical(cli2$chat, old_chat))                # NEW object (Route B)
  expect_identical(cli2$settings$model, "claude-haiku-4-5")
  expect_length(cli2$chat$get_turns(), 2L)                    # history migrated
  expect_gt(length(cli2$chat$get_tools()), 0L)               # tools re-registered
})

# ---------------------------------------------------------------------------
# Resolution + validation
# ---------------------------------------------------------------------------

test_that(".resolve_model_chat handles anthropic/ prefix", {
  ch <- .resolve_model_chat("anthropic/claude-haiku-4-5", cwd = getwd())
  expect_true(inherits(ch, "Chat"))
  expect_identical(ch$get_model(), "claude-haiku-4-5")
})

test_that("switch_model rejects bad inputs", {
  cli <- .mk_client()
  expect_error(switch_model("not a client", "anthropic/x"), "CodagentClient")
  expect_error(switch_model(cli, ""), "non-empty")
  expect_error(switch_model(cli, character(0)), "non-empty")
})
