stream_lifecycle_result <- function(value, timeout = 5) {
  if (inherits(value, "condition")) return(list(error = value))
  state <- new.env(parent = emptyenv())
  state$settled <- FALSE
  state$result <- NULL
  state$error <- NULL
  promises::then(value, function(result) {
    state$result <- result
    state$settled <- TRUE
    NULL
  }, function(error) {
    state$error <- error
    state$settled <- TRUE
    NULL
  })
  deadline <- Sys.time() + timeout
  while (!state$settled) {
    later::run_now(0.01)
    if (Sys.time() > deadline) stop("Stream lifecycle fixture did not settle")
  }
  list(result = state$result, error = state$error)
}

test_that("streaming reuses a small coroutine rather than building one per turn", {
  expect_false("coro::async" %in% all.names(body(codeagent_stream_async)))
  source <- paste(deparse(body(codeagent_stream_async)), collapse = "\n")
  expect_false(grepl("coro::async(", source, fixed = TRUE))
  driver <- get(".run_codeagent_stream", asNamespace("codeagent"), inherits = FALSE)
  fn <- get("fn", environment(driver), inherits = FALSE)
  expect_lte(length(deparse(body(fn))), 40L)
})

test_that("stream creation and error callback failures balance async turn tracking", {
  previous <- .async_turn_state$depth
  withr::defer(.async_turn_state$depth <- previous)
  local_mocked_bindings(
    .turn_setup = function(client, input, ...) input,
    .handle_agent_error = function(...) "recovered"
  )
  chat <- list(stream_async = function(...) stop("Synthetic stream startup failure"))
  value <- tryCatch(
    codeagent_stream_async(chat, "test",
      on_error = function(message, recovered) stop("Synthetic notification failure")),
    error = identity
  )
  observed <- stream_lifecycle_result(value)
  expect_s3_class(observed$error, "error")
  expect_match(conditionMessage(observed$error), "Synthetic notification failure")
  expect_identical(.async_turn_state$depth, previous)
})

test_that("interleaved streams keep independent text and release async ownership", {
  previous <- .async_turn_state$depth
  withr::defer(.async_turn_state$depth <- previous)
  local_mocked_bindings(
    .turn_setup = function(client, input, ...) input,
    .turn_teardown = function(...) list(n_tokens = 1L)
  )
  controls <- new.env(parent = emptyenv())
  make_chat <- function(name) {
    force(name)
    list(stream_async = function(...) {
      coro::async_generator(function() {
        coro::await(promises::promise(function(resolve, reject) {
          controls[[name]] <- resolve
        }))
        coro::yield(ellmer::ContentText(paste0(name, "-one ")))
        coro::yield(ellmer::ContentText(paste0(name, "-two")))
      })()
    })
  }
  first <- codeagent_stream_async(make_chat("first"), "one")
  second <- codeagent_stream_async(make_chat("second"), "two")
  deadline <- Sys.time() + 5
  while (!all(c("first", "second") %in% ls(controls))) {
    later::run_now(0.01)
    if (Sys.time() > deadline) stop("Streams did not start")
  }
  expect_identical(.async_turn_state$depth, previous + 2L)
  controls$second(NULL)
  second_result <- stream_lifecycle_result(second)
  expect_null(second_result$error)
  expect_identical(second_result$result$text, "second-one second-two")
  expect_identical(.async_turn_state$depth, previous + 1L)
  controls$first(NULL)
  first_result <- stream_lifecycle_result(first)
  expect_null(first_result$error)
  expect_identical(first_result$result$text, "first-one first-two")
  expect_identical(.async_turn_state$depth, previous)
})

test_that("a failed text callback waits for iterator cleanup before releasing ownership", {
  previous <- .async_turn_state$depth
  withr::defer(.async_turn_state$depth <- previous)
  local_mocked_bindings(
    .turn_setup = function(client, input, ...) input,
    .handle_agent_error = function(...) "recovered"
  )
  closed <- FALSE
  close_count <- 0L
  iterator <- function(close = FALSE) {
    if (close) {
      close_count <<- close_count + 1L
      return(promises::promise(function(resolve, reject) {
        later::later(function() {
          closed <<- TRUE
          resolve(NULL)
        }, 0.05)
      }))
    }
    promises::promise_resolve(ellmer::ContentText("partial text"))
  }
  reported <- NULL
  value <- codeagent_stream_async(
    list(stream_async = function(...) iterator), "test",
    on_delta = function(text) stop("Synthetic text callback failure"),
    on_error = function(message, recovered) reported <<- message
  )
  observed <- stream_lifecycle_result(value)
  expect_null(observed$error)
  expect_identical(observed$result$stop_reason, "error")
  expect_identical(observed$result$text, "partial text")
  expect_match(reported, "Synthetic text callback failure")
  expect_true(closed)
  expect_identical(close_count, 1L)
  expect_identical(.async_turn_state$depth, previous)
  deadline <- Sys.time() + 1
  while (!closed && Sys.time() < deadline) later::run_now(0.01)
})

test_that("stream callbacks and completion retain the caller promise domain", {
  local_mocked_bindings(
    .turn_setup = function(client, input, ...) input,
    .turn_teardown = function(...) list(n_tokens = 1L)
  )
  active <- FALSE
  seen <- logical()
  wrap <- function(callback) {
    force(callback)
    function(...) {
      previous <- active
      active <<- TRUE
      on.exit(active <<- previous)
      callback(...)
    }
  }
  domain <- promises::new_promise_domain(
    wrapOnFulfilled = wrap, wrapOnRejected = wrap,
    wrapSync = function(expr) {
      previous <- active
      active <<- TRUE
      on.exit(active <<- previous)
      force(expr)
    }
  )
  chat <- list(stream_async = function(...) {
    coro::async_generator(function() {
      for (index in seq_len(4L)) {
        coro::await(coro::async_sleep(0.001))
        coro::yield(ellmer::ContentText(as.character(index)))
      }
    })()
  })
  value <- promises::with_promise_domain(domain, codeagent_stream_async(
    chat, "test", on_delta = function(text) seen <<- c(seen, active),
    on_usage = function(usage) seen <<- c(seen, active)
  ))
  observed <- stream_lifecycle_result(value)
  expect_null(observed$error)
  expect_identical(observed$result$text, "1234")
  expect_identical(seen, rep(TRUE, 5L))
  expect_false(active)
})
