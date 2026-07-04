# Tests for Plan B mid-loop compaction: two-tier (budget-aware micro snip by
# default, opt-in full two-level compact) driven by on_tool_result.
# See references/plan/13-mid-loop-compaction.md.

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

# ellmer's S7 class is namespaced ("ellmer::ContentToolResult").
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

test_that("micro snip clears old tool results when enabled + over trigger", {
  chat <- .mk_chat_big_old_tool()
  skip_if(nchar(.first_tool_value(chat)) < 500, "chat setup lost big tool result")
  # model_limit tiny -> trigger negative -> always over; target 1 -> clear all;
  # keep 2 -> the old result (pos 2 of 5) is eligible.
  s <- list(midloop_compact = TRUE, model_limit = 100L,
            midloop_keep_recent = 2L, midloop_snip_target = 1L)
  expect_true(.midloop_compact_step(chat, s, ctrl = NULL))
  expect_identical(.first_tool_value(chat), .SNIP_PLACEHOLDER)
})

test_that("micro snip is budget-aware: no-op when payload already under target", {
  chat <- .mk_chat_big_old_tool()
  before <- .first_tool_value(chat)
  # huge target -> tool-result payload already under budget -> nothing cleared
  s <- list(midloop_compact = TRUE, model_limit = 100L,
            midloop_keep_recent = 2L, midloop_snip_target = 1000000L)
  expect_false(.midloop_compact_step(chat, s, ctrl = NULL))
  expect_identical(.first_tool_value(chat), before)
})

test_that("mid-loop is a no-op when disabled or under threshold", {
  chat <- .mk_chat_big_old_tool()
  before <- .first_tool_value(chat)
  expect_false(.midloop_compact_step(chat, list(midloop_compact = FALSE,
                                                model_limit = 100L)))
  expect_identical(.first_tool_value(chat), before)
  # enabled but under a realistic threshold
  expect_false(.midloop_compact_step(
    chat, list(midloop_compact = TRUE, model_limit = 200000L,
               midloop_keep_recent = 2L)))
  expect_identical(.first_tool_value(chat), before)
})

test_that("opt-in full path routes to controller compact_now, not snip", {
  chat <- .mk_chat_big_old_tool()
  before <- .first_tool_value(chat)
  called <- new.env(); called$hit <- FALSE
  stub <- list(compact_now = function(chat, model) { called$hit <- TRUE; TRUE })
  s <- list(midloop_compact = TRUE, midloop_full_compact = TRUE, model_limit = 100L)
  expect_true(.midloop_compact_step(chat, s, ctrl = stub))
  expect_true(called$hit)                              # full path taken
  expect_identical(.first_tool_value(chat), before)    # snip NOT used
})

test_that("register_midloop_compaction wires an on_tool_result callback that snips", {
  chat <- .mk_chat_big_old_tool()
  skip_if(nchar(.first_tool_value(chat)) < 500, "chat setup lost big tool result")
  s <- list(midloop_compact = TRUE, model_limit = 100L,
            midloop_keep_recent = 2L, midloop_snip_target = 1L)
  register_midloop_compaction(chat, s)
  pe <- environment(chat$chat)$private
  suppressMessages(pe$callback_on_tool_result$invoke(
    ellmer::ContentToolResult(value = "dummy")))
  expect_identical(.first_tool_value(chat), .SNIP_PLACEHOLDER)
})

test_that("mid-loop enable flags honour settings and options", {
  expect_false(.midloop_enabled(list()))
  expect_true(.midloop_enabled(list(midloop_compact = TRUE)))
  expect_false(.midloop_full_enabled(list()))
  expect_true(.midloop_full_enabled(list(midloop_full_compact = TRUE)))
  withr::local_options(codeagent.midloop_compact = TRUE,
                       codeagent.midloop_full_compact = TRUE)
  expect_true(.midloop_enabled(list()))
  expect_true(.midloop_full_enabled(list()))
})

test_that("snip_old_tools target_tokens stops early once under budget", {
  chat <- .mk_chat_big_old_tool()
  # target above current payload -> should not modify anything
  expect_false(isTRUE(snip_old_tools(chat, keep_recent_turns = 2L,
                                     target_tokens = 1000000L)))
})
