# Tests for Plan B mid-loop compaction (snip old tool results between tool
# rounds via on_tool_result). See references/plan/13-mid-loop-compaction.md.

# Build a chat whose EARLY turns contain a large tool result (snip candidate),
# with recent turns after it.
.mk_chat_big_old_tool <- function() {
  chat <- ellmer::chat_openai_compatible(base_url = "http://x", model = "m",
                                         credentials = function() "k")
  big <- strrep("x", 1200)   # > snip min_chars (500)
  turns <- list(
    ellmer::Turn("user", list(ellmer::ContentText("question 1"))),
    ellmer::Turn("user", list(ellmer::ContentToolResult(value = big))),
    ellmer::Turn("user", list(ellmer::ContentText("question 2"))),
    ellmer::Turn("assistant", list(ellmer::ContentText("recent answer"))),
    ellmer::Turn("user", list(ellmer::ContentText("question 3")))
  )
  tryCatch(chat$set_turns(turns), error = function(e) NULL)
  chat
}

.first_tool_value <- function(chat) {
  is_tr <- function(ct) tryCatch(
    inherits(ct, "ellmer::ContentToolResult") ||
      identical(class(ct)[[1L]], "ContentToolResult"),
    error = function(e) FALSE)
  for (t in chat$get_turns()) {
    for (ct in t@contents) {
      if (is_tr(ct))
        return(tryCatch(as.character(ct@value), error = function(e) NA_character_))
    }
  }
  NA_character_
}

test_that(".midloop_maybe_snip snips old tool results when enabled + over threshold", {
  withr::local_options(codeagent.midloop_keep_recent = 2L)
  chat <- .mk_chat_big_old_tool()
  skip_if(nchar(.first_tool_value(chat)) < 500, "chat setup did not retain big tool result")
  # tiny model_limit -> threshold is negative -> always "over"
  s <- list(midloop_compact = TRUE, model_limit = 100L, midloop_keep_recent = 2L)
  did <- .midloop_maybe_snip(chat, s)
  expect_true(did)
  expect_identical(.first_tool_value(chat), .SNIP_PLACEHOLDER)
})

test_that(".midloop_maybe_snip is a no-op when disabled", {
  chat <- .mk_chat_big_old_tool()
  before <- .first_tool_value(chat)
  s <- list(midloop_compact = FALSE, model_limit = 100L)
  expect_false(.midloop_maybe_snip(chat, s))
  expect_identical(.first_tool_value(chat), before)   # unchanged
})

test_that(".midloop_maybe_snip is a no-op when under threshold", {
  chat <- .mk_chat_big_old_tool()
  before <- .first_tool_value(chat)
  # large model_limit -> threshold ~167k, tiny estimate -> under
  s <- list(midloop_compact = TRUE, model_limit = 200000L, midloop_keep_recent = 2L)
  expect_false(.midloop_maybe_snip(chat, s))
  expect_identical(.first_tool_value(chat), before)
})

test_that("register_midloop_compaction wires an on_tool_result callback that snips", {
  chat <- .mk_chat_big_old_tool()
  skip_if(nchar(.first_tool_value(chat)) < 500, "chat setup did not retain big tool result")
  s <- list(midloop_compact = TRUE, model_limit = 100L, midloop_keep_recent = 2L)
  register_midloop_compaction(chat, s)
  # Fire the tool-result callbacks as the tool loop would, mid-round.
  pe <- environment(chat$chat)$private
  suppressMessages(pe$callback_on_tool_result$invoke(
    ellmer::ContentToolResult(value = "dummy")))
  expect_identical(.first_tool_value(chat), .SNIP_PLACEHOLDER)
})

test_that(".midloop_enabled honours settings flag and option", {
  expect_false(.midloop_enabled(list()))
  expect_true(.midloop_enabled(list(midloop_compact = TRUE)))
  withr::local_options(codeagent.midloop_compact = TRUE)
  expect_true(.midloop_enabled(list()))
})
