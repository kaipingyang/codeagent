# tests/testthat/test-codeagent-stream.R
# Unit tests for R/stream.R: codeagent_stream_async + codeagent_stream.
# Uses duck-typed fake chat objects (list-based) to avoid real API calls.

library(ellmer)

# ---------------------------------------------------------------------------
# Helpers: fake chat and fake generator
# ---------------------------------------------------------------------------

.mk_fake_gen <- function(chunks) {
  force(chunks)
  coro::async_generator(function() {
    for (ch in chunks) coro::yield(ch)
  })
}

.mk_fake_chat <- function(chunks) {
  list(
    stream_async    = function(...) .mk_fake_gen(chunks)(),
    get_tokens      = function(...) data.frame(input = 10L, output = 5L,
                                               cached_input = 0L, cost = 0.001),
    get_cost        = function(include = "all") 0.001,
    on_tool_request = function(cb) invisible(NULL),
    on_tool_result  = function(cb) invisible(NULL),
    get_turns       = function(...) list()
  )
}

# Pump a coro::async promise to completion in a test (no Shiny event loop).
.pump <- function(p, timeout_s = 5) {
  done <- FALSE; result <- NULL
  promises::then(p, function(r) { result <<- r; done <<- TRUE })
  t <- Sys.time() + timeout_s
  while (!isTRUE(done) && Sys.time() < t) later::run_now(timeoutSecs = 0.1)
  result
}

# ---------------------------------------------------------------------------
# codeagent_stream_async: text / thinking / tool events
# ---------------------------------------------------------------------------

test_that("codeagent_stream_async collects text chunks via on_delta", {
  skip_if_not_installed("coro"); skip_if_not_installed("promises")
  skip_if_not_installed("later")

  chunks <- list(ContentText("hello "), ContentText("world"))
  chat   <- .mk_fake_chat(chunks)

  deltas <- character(0)
  p <- codeagent_stream_async(chat, "test",
                               on_delta = function(t) deltas <<- c(deltas, t))
  result <- .pump(p)

  expect_equal(paste(deltas, collapse = ""), "hello world")
  expect_equal(result$text, "hello world")
  expect_equal(result$stop_reason, "completed")
})

test_that("codeagent_stream_async fires on_thinking for ContentThinking chunks", {
  skip_if_not_installed("coro"); skip_if_not_installed("promises")
  skip_if_not_installed("later")

  chunks <- list(ContentThinking(thinking = "hmm..."), ContentText("answer"))
  chat   <- .mk_fake_chat(chunks)

  thinkings <- character(0); deltas <- character(0)
  p <- codeagent_stream_async(chat, "test",
    on_thinking = function(t) thinkings <<- c(thinkings, t),
    on_delta    = function(t) deltas    <<- c(deltas, t))
  result <- .pump(p)

  expect_equal(thinkings, "hmm...")
  expect_equal(deltas, "answer")
  expect_equal(result$text, "answer")
})

test_that("codeagent_stream_async fires on_tool_request from ContentToolRequest chunk", {
  skip_if_not_installed("coro"); skip_if_not_installed("promises")
  skip_if_not_installed("later")

  req    <- ContentToolRequest(id = "r1", name = "Bash",
                               arguments = list(command = "ls"))
  chunks <- list(ContentText("Running... "), req)
  chat   <- .mk_fake_chat(chunks)

  tool_reqs <- list()
  p <- codeagent_stream_async(chat, "test",
    on_tool_request = function(r) tool_reqs[[length(tool_reqs)+1L]] <<- r)
  .pump(p)

  expect_length(tool_reqs, 1L)
  expect_equal(tool_reqs[[1L]]$id,   "r1")
  expect_equal(tool_reqs[[1L]]$name, "Bash")
})

test_that("codeagent_stream_async fires on_tool_result with display field", {
  skip_if_not_installed("coro"); skip_if_not_installed("promises")
  skip_if_not_installed("later")

  req    <- ContentToolRequest(id = "r1", name = "Read",
                               arguments = list(file_path = "R/utils.R"))
  res    <- ContentToolResult(value = "100 lines", request = req)
  chunks <- list(req, res)
  chat   <- .mk_fake_chat(chunks)

  tool_results <- list()
  p <- codeagent_stream_async(chat, "test",
    on_tool_result = function(r) tool_results[[length(tool_results)+1L]] <<- r)
  .pump(p)

  expect_length(tool_results, 1L)
  tr <- tool_results[[1L]]
  expect_equal(tr$name, "Read")
  expect_true("display" %in% names(tr))
  expect_false(tr$is_error)
})

test_that("codeagent_stream_async fires on_error and returns stop_reason error", {
  skip_if_not_installed("coro"); skip_if_not_installed("promises")
  skip_if_not_installed("later")

  # Chat whose stream_async always throws
  chat <- list(
    stream_async    = function(...) {
      coro::async_generator(function() { stop("network error"); coro::yield("x") })()
    },
    get_tokens   = function(...) data.frame(input=0L,output=0L,cached_input=0L,cost=0),
    get_cost     = function(...) NA_real_,
    on_tool_request = function(cb) invisible(NULL),
    on_tool_result  = function(cb) invisible(NULL),
    get_turns    = function(...) list()
  )

  errors <- character(0)
  p <- codeagent_stream_async(chat, "test",
    on_error = function(msg, rec) errors <<- c(errors, msg))
  result <- .pump(p)

  expect_equal(result$stop_reason, "error")
  expect_length(errors, 1L)
  expect_true(nzchar(errors[[1L]]))
})

test_that("codeagent_stream_async acc visible in error handler (partial text returned)", {
  skip_if_not_installed("coro"); skip_if_not_installed("promises")
  skip_if_not_installed("later")

  # Stream: two text chunks then throws
  chat <- list(
    stream_async = function(...) {
      coro::async_generator(function() {
        coro::yield(ContentText("partial"))
        stop("mid-stream error")
      })()
    },
    get_tokens   = function(...) data.frame(input=0L,output=0L,cached_input=0L,cost=0),
    get_cost     = function(...) NA_real_,
    on_tool_request = function(cb) invisible(NULL),
    on_tool_result  = function(cb) invisible(NULL),
    get_turns    = function(...) list()
  )

  p <- codeagent_stream_async(chat, "test")
  result <- .pump(p)

  expect_equal(result$stop_reason, "error")
  # acc ("partial") should be visible in the error path
  expect_equal(result$text, "partial")
})

# ---------------------------------------------------------------------------
# codeagent_stream: synchronous wrapper
# ---------------------------------------------------------------------------

test_that("codeagent_stream returns full text synchronously", {
  skip_if_not_installed("coro"); skip_if_not_installed("promises")
  skip_if_not_installed("later")

  chunks <- list(ContentText("sync "), ContentText("result"))
  chat   <- .mk_fake_chat(chunks)

  deltas <- character(0)
  result <- codeagent_stream(chat, "test",
                              on_delta = function(t) deltas <<- c(deltas, t))

  expect_equal(paste(deltas, collapse = ""), "sync result")
  expect_equal(result$text, "sync result")
  expect_equal(result$stop_reason, "completed")
})

test_that("codeagent_stream usage contains cost_last field", {
  skip_if_not_installed("coro"); skip_if_not_installed("promises")
  skip_if_not_installed("later")

  chunks <- list(ContentText("hi"))
  chat   <- .mk_fake_chat(chunks)

  result <- codeagent_stream(chat, "test")

  expect_true(!is.null(result$usage))
  expect_true("cost_last" %in% names(result$usage))
})
