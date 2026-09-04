# Tests for upstream per-request mid-loop compaction: budget-aware micro snip
# by default, with an opt-in full two-level compact, driven by on_request_start.

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

test_that("opt-in full path delegates to controller adaptive pipeline", {
  chat <- .mk_chat_big_old_tool()
  before <- .first_tool_value(chat)
  called <- new.env(parent = emptyenv())
  called$full_enabled <- FALSE
  stub <- list(adaptive_compact = function(chat, settings, model,
                                           compact_model, request_turns,
                                           full_enabled, hooks = NULL) {
    called$full_enabled <- full_enabled
    .new_compaction_decision(
      "full_summary", "summary_sufficient", 500L, 50L, 100L,
      changed = TRUE, summary_calls = 1L
    )
  })
  settings <- list(
    midloop_compact = TRUE,
    midloop_full_compact = TRUE,
    model_limit = 100L
  )

  result <- .midloop_compact_step(chat, settings, ctrl = stub)

  expect_true(result)
  expect_true(called$full_enabled)
  expect_identical(attr(result, "decision")$action, "full_summary")
  expect_identical(.first_tool_value(chat), before)
})

test_that("outgoing turn estimates include pending tool results", {
  pending <- ellmer::Turn(
    "user",
    list(ellmer::ContentToolResult(value = strrep("p", 3500)))
  )
  expect_gt(.estimate_turns_tokens(list(pending)), 900L)
})

test_that("pending outgoing turns can trigger mid-loop compaction", {
  chat <- .mk_chat_big_old_tool()
  before <- .first_tool_value(chat)
  history_tokens <- token_count_with_estimation(chat, allow_network = FALSE)
  pending <- ellmer::Turn(
    "user",
    list(ellmer::ContentToolResult(value = strrep("p", 3500)))
  )
  outgoing <- c(chat$get_turns(include_system_prompt = TRUE), list(pending))
  threshold <- history_tokens + 100L
  expect_gt(.estimate_turns_tokens(outgoing), threshold)

  s <- list(
    midloop_compact = TRUE,
    midloop_threshold = threshold,
    midloop_keep_recent = 2L,
    midloop_snip_target = 1L
  )
  expect_true(.midloop_compact_step(
    chat,
    s,
    ctrl = NULL,
    request_turns = outgoing
  ))
  expect_false(identical(.first_tool_value(chat), before))
  expect_identical(.first_tool_value(chat), .SNIP_PLACEHOLDER)
})

test_that("register_midloop_compaction uses on_request_start, not tool results", {
  chat <- .mk_chat_big_old_tool()
  skip_if(nchar(.first_tool_value(chat)) < 500, "chat setup lost big tool result")
  before <- .first_tool_value(chat)
  s <- list(midloop_compact = TRUE, model_limit = 100L,
            midloop_keep_recent = 2L, midloop_snip_target = 1L)
  register_midloop_compaction(chat, s)
  pe <- environment(chat$chat)$private

  pe$callback_on_tool_result$invoke(
    ellmer::ContentToolResult(value = "dummy"))
  expect_identical(.first_tool_value(chat), before)

  outgoing <- c(
    chat$get_turns(include_system_prompt = TRUE),
    list(ellmer::Turn("user", list(ellmer::ContentText("pending"))))
  )
  suppressMessages(pe$callback_on_request_start$invoke(outgoing))
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

# --- Adaptive compaction: outgoing request snapshots ------------------------

test_that("outgoing snapshot rebuild appends the original pending turn once", {
  chat <- ellmer::chat_openai_compatible(
    base_url = "http://x", model = "m", credentials = function() "k")
  chat$set_turns(list(
    ellmer::Turn("user", list(ellmer::ContentText("old history"))),
    ellmer::Turn("assistant", list(ellmer::ContentText("old answer")))
  ))
  pending <- ellmer::Turn(
    "user", list(ellmer::ContentText("UNIQUE_PENDING_SENTINEL")))
  outgoing <- c(chat$get_turns(include_system_prompt = TRUE), list(pending))

  initial <- .build_outgoing_snapshot(
    chat,
    request_turns = outgoing,
    use_provider_usage = TRUE
  )
  chat$set_turns(list(
    ellmer::Turn("user", list(ellmer::ContentText("new compacted history")))
  ))
  rebuilt <- .build_outgoing_snapshot(
    chat,
    pending_turn = initial$pending_turn,
    use_provider_usage = FALSE
  )
  serialized <- .serialize_compact_turns(rebuilt$turns)

  expect_identical(initial$pending_turn, pending)
  expect_identical(
    lengths(regmatches(serialized, gregexpr(
      "UNIQUE_PENDING_SENTINEL", serialized, fixed = TRUE))),
    1L
  )
  expect_match(serialized, "new compacted history", fixed = TRUE)
  expect_false(grepl("old history", serialized, fixed = TRUE))
})

test_that("fresh outgoing recount ignores stale provider usage", {
  pending <- ellmer::Turn("user", list(ellmer::ContentText("pending")))
  fake <- list(
    get_tokens = function(...) data.frame(
      input = 900000L, output = 1000L, cached_input = 0L, cost = 0),
    get_turns = function(...) list(
      ellmer::Turn("user", list(ellmer::ContentText("small history"))))
  )

  initial <- .build_outgoing_snapshot(
    fake,
    request_turns = c(fake$get_turns(), list(pending)),
    use_provider_usage = TRUE
  )
  rebuilt <- .build_outgoing_snapshot(
    fake,
    pending_turn = pending,
    use_provider_usage = FALSE
  )

  expect_gt(initial$tokens, 900000L)
  expect_lt(rebuilt$tokens, 100L)
  expect_identical(rebuilt$tokens, rebuilt$structural_tokens)
})

# --- Adaptive compaction: cheap-to-expensive decisions ----------------------

test_that("adaptive pipeline stops after a sufficient micro snip", {
  chat <- ellmer::chat_openai_compatible(
    base_url = "http://x", model = "m", credentials = function() "k")
  chat$set_turns(list(ellmer::Turn(
    "user", list(ellmer::ContentText(strrep("x", 3000))))))
  pending <- ellmer::Turn("user", list(ellmer::ContentText("pending")))
  outgoing <- c(chat$get_turns(include_system_prompt = TRUE), list(pending))
  summary_calls <- 0L
  local_mocked_bindings(
    snip_old_tools = function(chat, ...) {
      chat$set_turns(list(ellmer::Turn(
        "user", list(ellmer::ContentText("small")))))
      TRUE
    },
    session_memory_compact = function(...) {
      summary_calls <<- summary_calls + 1L
      TRUE
    },
    full_compact = function(...) {
      summary_calls <<- summary_calls + 1L
      TRUE
    }
  )

  decision <- .adaptive_compact_pipeline(
    chat,
    settings = list(
      midloop_threshold = 100L,
      midloop_keep_recent = 0L,
      midloop_snip_target = 1L
    ),
    model = "m",
    compact_model = "compact-model",
    request_turns = outgoing,
    full_enabled = TRUE
  )

  expect_identical(decision$action, "micro_snip")
  expect_identical(decision$reason, "cheap_reduction_sufficient")
  expect_identical(decision$summary_calls, 0L)
  expect_identical(summary_calls, 0L)
  expect_lt(decision$after_estimate, decision$threshold)
})

test_that("adaptive pipeline reports over-threshold when full is disabled", {
  chat <- ellmer::chat_openai_compatible(
    base_url = "http://x", model = "m", credentials = function() "k")
  chat$set_turns(list(ellmer::Turn(
    "user", list(ellmer::ContentText(strrep("x", 3000))))))
  summary_calls <- 0L
  local_mocked_bindings(
    snip_old_tools = function(...) FALSE,
    session_memory_compact = function(...) {
      summary_calls <<- summary_calls + 1L
      TRUE
    },
    full_compact = function(...) {
      summary_calls <<- summary_calls + 1L
      TRUE
    }
  )

  decision <- .adaptive_compact_pipeline(
    chat,
    settings = list(midloop_threshold = 100L),
    model = "m",
    compact_model = "compact-model",
    full_enabled = FALSE
  )

  expect_identical(decision$action, "none")
  expect_identical(decision$reason, "over_threshold_full_disabled")
  expect_identical(decision$summary_calls, 0L)
  expect_identical(summary_calls, 0L)
  expect_false(decision$success)
})

test_that("adaptive pipeline calls incremental summary once then stops", {
  chat <- ellmer::chat_openai_compatible(
    base_url = "http://x", model = "m", credentials = function() "k")
  chat$set_turns(list(ellmer::Turn(
    "user", list(ellmer::ContentText(strrep("x", 3000))))))
  calls <- character(0)
  local_mocked_bindings(
    snip_old_tools = function(...) FALSE,
    session_memory_compact = function(chat, ...) {
      calls <<- c(calls, "incremental")
      chat$set_turns(list(ellmer::Turn(
        "user", list(ellmer::ContentText("small summary")))))
      TRUE
    },
    full_compact = function(...) {
      calls <<- c(calls, "full")
      TRUE
    }
  )

  decision <- .adaptive_compact_pipeline(
    chat,
    settings = list(midloop_threshold = 100L),
    model = "m",
    compact_model = "compact-model",
    full_enabled = TRUE
  )

  expect_identical(calls, "incremental")
  expect_identical(decision$action, "incremental_summary")
  expect_identical(decision$summary_calls, 1L)
  expect_lt(decision$after_estimate, decision$threshold)
})

test_that("adaptive pipeline falls back to full summary exactly once", {
  chat <- ellmer::chat_openai_compatible(
    base_url = "http://x", model = "m", credentials = function() "k")
  chat$set_turns(list(ellmer::Turn(
    "user", list(ellmer::ContentText(strrep("x", 3000))))))
  calls <- character(0)
  local_mocked_bindings(
    snip_old_tools = function(...) FALSE,
    session_memory_compact = function(...) {
      calls <<- c(calls, "incremental_unavailable")
      FALSE
    },
    full_compact = function(chat, ...) {
      calls <<- c(calls, "full")
      chat$set_turns(list(ellmer::Turn(
        "user", list(ellmer::ContentText("small full summary")))))
      TRUE
    }
  )

  decision <- .adaptive_compact_pipeline(
    chat,
    settings = list(midloop_threshold = 100L),
    model = "m",
    compact_model = "compact-model",
    full_enabled = TRUE
  )

  expect_identical(calls, c("incremental_unavailable", "full"))
  expect_identical(decision$action, "full_summary")
  expect_identical(decision$summary_calls, 1L)
  expect_true(decision$success)
})

test_that("adaptive pipeline reports when summaries remain too large", {
  chat <- ellmer::chat_openai_compatible(
    base_url = "http://x", model = "m", credentials = function() "k")
  chat$set_turns(list(ellmer::Turn(
    "user", list(ellmer::ContentText(strrep("x", 3000))))))
  local_mocked_bindings(
    snip_old_tools = function(...) FALSE,
    session_memory_compact = function(...) TRUE,
    full_compact = function(...) TRUE
  )

  decision <- .adaptive_compact_pipeline(
    chat,
    settings = list(midloop_threshold = 100L),
    model = "m",
    compact_model = "compact-model",
    full_enabled = TRUE
  )

  expect_identical(decision$action, "full_summary")
  expect_identical(decision$reason, "post_compact_still_large")
  expect_identical(decision$summary_calls, 2L)
  expect_false(decision$success)
  expect_gte(decision$after_estimate, decision$threshold)
})

test_that("adaptive pipeline is a no-op below threshold", {
  chat <- ellmer::chat_openai_compatible(
    base_url = "http://x", model = "m", credentials = function() "k")
  chat$set_turns(list(ellmer::Turn(
    "user", list(ellmer::ContentText("small history")))))
  snip_calls <- 0L
  local_mocked_bindings(
    snip_old_tools = function(...) {
      snip_calls <<- snip_calls + 1L
      TRUE
    }
  )

  decision <- .adaptive_compact_pipeline(
    chat,
    settings = list(midloop_threshold = 1000L),
    model = "m",
    full_enabled = TRUE
  )

  expect_identical(decision$action, "none")
  expect_identical(decision$reason, "below_threshold")
  expect_identical(snip_calls, 0L)
  expect_true(decision$success)
})

test_that("stale provider usage cannot force summary after successful snip", {
  state <- new.env(parent = emptyenv())
  state$turns <- list(ellmer::Turn(
    "user", list(ellmer::ContentText(strrep("x", 3000)))))
  fake <- list(
    get_tokens = function(...) data.frame(
      input = 900000L, output = 1000L, cached_input = 0L, cost = 0),
    get_turns = function(...) state$turns,
    set_turns = function(turns) state$turns <- turns
  )
  pending <- ellmer::Turn("user", list(ellmer::ContentText("pending")))
  outgoing <- c(state$turns, list(pending))
  summary_calls <- 0L
  local_mocked_bindings(
    snip_old_tools = function(chat, ...) {
      chat$set_turns(list(ellmer::Turn(
        "user", list(ellmer::ContentText("small")))))
      TRUE
    },
    session_memory_compact = function(...) {
      summary_calls <<- summary_calls + 1L
      TRUE
    },
    full_compact = function(...) {
      summary_calls <<- summary_calls + 1L
      TRUE
    }
  )

  decision <- .adaptive_compact_pipeline(
    fake,
    settings = list(midloop_threshold = 100L),
    model = "m",
    request_turns = outgoing,
    full_enabled = TRUE
  )

  expect_gt(decision$before_estimate, 900000L)
  expect_lt(decision$after_estimate, 100L)
  expect_identical(decision$reason, "cheap_reduction_sufficient")
  expect_identical(summary_calls, 0L)
})

# --- Adaptive compaction: lifecycle metadata --------------------------------

test_that("compaction lifecycle fires only for a selected action", {
  events <- list()
  hooks <- HookRegistry$new()
  hooks$register(HookEvent$PRE_COMPACT, function(level, context) {
    events[[length(events) + 1L]] <<- list(
      event = "pre", level = level, context = context)
  })
  hooks$register(HookEvent$POST_COMPACT, function(trigger, summary, context) {
    events[[length(events) + 1L]] <<- list(
      event = "post", trigger = trigger, summary = summary,
      context = context)
  })
  chat <- ellmer::chat_openai_compatible(
    base_url = "http://x", model = "m", credentials = function() "k")
  chat$set_turns(list(ellmer::Turn(
    "user", list(ellmer::ContentText("RAW_TURN_SENTINEL")))))
  ctrl <- CompactionController$new()

  below <- ctrl$adaptive_compact(
    chat,
    settings = list(midloop_threshold = 1000L),
    model = "m",
    hooks = hooks,
    full_enabled = TRUE
  )
  expect_identical(below$reason, "below_threshold")
  expect_length(events, 0L)

  local_mocked_bindings(
    snip_old_tools = function(chat, ...) {
      chat$set_turns(list(ellmer::Turn(
        "user", list(ellmer::ContentText("small")))))
      TRUE
    }
  )
  acted <- ctrl$adaptive_compact(
    chat,
    settings = list(midloop_threshold = 1L),
    model = "m",
    hooks = hooks,
    full_enabled = FALSE
  )

  expect_true(acted$changed)
  expect_identical(vapply(events, `[[`, character(1L), "event"),
                   c("pre", "post"))
  expect_identical(events[[1L]]$level, "adaptive")
  expect_identical(events[[2L]]$trigger, "auto")
  expect_identical(events[[2L]]$summary, "")
  payload <- paste(capture.output(str(events)), collapse = "\n")
  expect_false(grepl("RAW_TURN_SENTINEL", payload, fixed = TRUE))
  expect_true(all(c(
    "action", "reason", "before_estimate", "after_estimate",
    "threshold", "duration_ms", "success"
  ) %in% names(events[[2L]]$context)))
})

test_that("post-compact still-large failures open the circuit breaker", {
  summary_calls <- 0L
  local_mocked_bindings(
    .build_outgoing_snapshot = function(...) list(
      turns = list(), pending_turn = NULL,
      structural_tokens = 1000L, provider_tokens = NA_integer_,
      tokens = 1000L
    ),
    snip_old_tools = function(...) FALSE,
    session_memory_compact = function(...) {
      summary_calls <<- summary_calls + 1L
      TRUE
    },
    full_compact = function(...) {
      summary_calls <<- summary_calls + 1L
      TRUE
    }
  )
  ctrl <- CompactionController$new()
  limit <- .COMPACT_CIRCUIT_BREAKER_LIMIT

  for (i in seq_len(limit)) {
    decision <- ctrl$adaptive_compact(
      chat = list(),
      settings = list(midloop_threshold = 100L),
      full_enabled = TRUE
    )
    expect_identical(decision$reason, "post_compact_still_large")
  }
  expect_identical(ctrl$failure_count(), limit)
  calls_before <- summary_calls
  blocked <- ctrl$adaptive_compact(
    chat = list(),
    settings = list(midloop_threshold = 100L),
    full_enabled = TRUE
  )
  expect_identical(blocked$reason, "circuit_open")
  expect_identical(summary_calls, calls_before)
})

test_that("resource mutations request a fresh structural initial count", {
  fake <- list(
    get_tokens = function(...) data.frame(
      input = 900000L, output = 1000L, cached_input = 0L, cost = 0),
    get_turns = function(...) list(ellmer::Turn(
      "user", list(ellmer::ContentText("small after resource replacement"))))
  )
  snip_calls <- 0L
  local_mocked_bindings(
    snip_old_tools = function(...) {
      snip_calls <<- snip_calls + 1L
      FALSE
    }
  )
  ctrl <- CompactionController$new()

  decision <- ctrl$adaptive_compact(
    fake,
    settings = list(midloop_threshold = 100L),
    full_enabled = FALSE,
    use_provider_usage = FALSE
  )

  expect_identical(decision$reason, "below_threshold")
  expect_lt(decision$before_estimate, 100L)
  expect_identical(snip_calls, 0L)
})

test_that("partial mutation errors report changed state and PostCompact", {
  req <- ellmer::ContentToolRequest(
    id = "partial-tool", name = "Tool", arguments = list())
  chat <- ellmer::chat_openai_compatible(
    base_url = "http://x", model = "m", credentials = function() "k")
  chat$set_turns(list(
    ellmer::Turn("assistant", list(req)),
    ellmer::Turn("user", list(ellmer::ContentToolResult(
      request = req, value = strrep("x", 1500)))),
    ellmer::Turn("user", list(ellmer::ContentText("latest")))
  ))
  events <- character(0)
  hooks <- HookRegistry$new()
  hooks$register(HookEvent$PRE_COMPACT, function(...) {
    events <<- c(events, "pre")
  })
  hooks$register(HookEvent$POST_COMPACT, function(...) {
    events <<- c(events, "post")
  })
  local_mocked_bindings(
    snip_old_tools = function(chat, ...) {
      turns <- chat$get_turns()
      turns[[2L]]@contents[[1L]]@value <- "small"
      chat$set_turns(turns)
      TRUE
    },
    session_memory_compact = function(...) stop("synthetic summary failure")
  )
  ctrl <- CompactionController$new()

  decision <- suppressWarnings(ctrl$adaptive_compact(
    chat,
    settings = list(midloop_threshold = 1L),
    full_enabled = TRUE,
    hooks = hooks
  ))

  expect_identical(decision$reason, "callback_error")
  expect_true(decision$changed)
  expect_false(decision$success)
  expect_identical(events, c("pre", "post"))
  expect_identical(ctrl$failure_count(), 1L)
})
