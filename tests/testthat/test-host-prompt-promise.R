wait_for <- function(p, secs = 5) {
  out <- NULL; done <- FALSE
  promises::then(p, function(v) { out <<- v; done <<- TRUE })
  t0 <- Sys.time()
  while (!done && difftime(Sys.time(), t0, units = "secs") < secs) later::run_now(0.05)
  out
}

test_that("a promise from on_user_prompt is kept for the turn, not sent as text", {
  pending <- new.env()
  reg <- .host_prompt_hook(NULL, function(text) promises::promise_resolve("keys: t_dm"), pending)
  res <- reg$run_user_prompt_submit("hello")
  expect_null(res$additional_context)
  expect_true(promises::is.promise(pending$p))
  reg2 <- .host_prompt_hook(NULL, function(text) "now", new.env())
  expect_match(reg2$run_user_prompt_submit("hi")$additional_context, "now")
})

test_that("the turn waits for the promise, at most prompt_wait seconds", {
  expect_identical(wait_for(.await_host_context(promises::promise_resolve("keys: t_dm"), 2)), "keys: t_dm")
  slow <- promises::promise(function(resolve, reject) later::later(function() resolve("late"), 3))
  t0 <- Sys.time(); expect_null(wait_for(.await_host_context(slow, 0.5)))
  expect_lt(as.numeric(difftime(Sys.time(), t0, units = "secs")), 2.5)
  expect_null(wait_for(.await_host_context(promises::promise_reject(simpleError("x")), 2)))
  expect_null(wait_for(.await_host_context(promises::promise_resolve(NULL), 2)))
})

test_that("codeagent_server checks prompt_wait and the chat waits before its first request", {
  expect_true("prompt_wait" %in% names(formals(codeagent_server)))
  src <- paste(deparse(body(server_chat)), collapse = "\n")
  expect_match(src, "continue_after_host", fixed = TRUE)
  expect_match(src, "host_prompt_pending$p <- NULL", fixed = TRUE)
})
