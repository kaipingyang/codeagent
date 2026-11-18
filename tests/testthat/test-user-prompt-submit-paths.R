# UserPromptSubmit hooks on the entry points that do not go through
# agent_loop(): the Shiny chat (server_chat), codeagent_stream_async() and,
# through it, the REPL.

ups_registry <- function(fn) {
  reg <- HookRegistry$new()
  reg$register(HookEvent$USER_PROMPT_SUBMIT, fn)
  reg
}

ups_settle <- function(p, timeout = 5) {
  state <- new.env(parent = emptyenv())
  state$done <- FALSE
  promises::then(p, function(v) { state$value <- v; state$done <- TRUE },
                 function(e) { state$error <- e; state$done <- TRUE })
  deadline <- Sys.time() + timeout
  while (!state$done) {
    later::run_now(0.01)
    if (Sys.time() > deadline) stop("promise did not settle")
  }
  if (!is.null(state$error)) stop(state$error)
  state$value
}

test_that(".run_user_prompt_submit returns allow with no registry", {
  expect_identical(.run_user_prompt_submit(list(), "hi"),
                   list(action = "allow", additional_context = NULL))
})

test_that(".run_user_prompt_submit passes the typed text, without reminders", {
  seen <- NULL
  reg <- ups_registry(function(message) {
    seen <<- message
    list(action = "add_context", additional_context = "CTX")
  })
  input <- list("draw a plot\n\n<system-reminder>\nnoise\n</system-reminder>",
                ellmer::ContentText("attachment"))
  out <- .run_user_prompt_submit(list(hooks_registry = reg), input)
  expect_identical(seen, "draw a plot")
  expect_identical(out$action, "allow")
  expect_identical(out$additional_context, "CTX")
})

test_that(".run_user_prompt_submit reports a block", {
  reg <- ups_registry(function(message) list(action = "block", message = "nope"))
  out <- .run_user_prompt_submit(list(hooks_registry = reg), "x")
  expect_identical(out$action, "block")
  expect_identical(out$message, "nope")
})

test_that("a failing hook registry never blocks the turn", {
  broken <- list(run_user_prompt_submit = function(message) stop("boom"))
  out <- .run_user_prompt_submit(list(hooks_registry = broken), "x")
  expect_identical(out$action, "allow")
})

test_that(".turn_setup appends hook context after the system-reminder", {
  client <- structure(list(chat = NULL, settings = list()), class = "CodeagentClient")
  out <- .turn_setup(client, "question", iteration = 2L, cwd = tempdir(),
                     additional_context = "SCOPE: s1-1")
  expect_match(out, "^question\n\n<system-reminder>")
  expect_match(out, "</system-reminder>\n\nSCOPE: s1-1$")
  # list input (text + attachments): context goes to the text part
  att <- ellmer::ContentText("a")
  out_l <- .turn_setup(client, list("q", att), iteration = 2L, cwd = tempdir(),
                       additional_context = "CTX")
  expect_match(out_l[[1]], "CTX$")
  expect_identical(out_l[[2]], att)
  # no context: unchanged behaviour
  expect_false(grepl("CTX", .turn_setup(client, "q", iteration = 2L, cwd = tempdir())))
})

test_that("codeagent_stream_async sends hook context to the model", {
  local_mocked_bindings(.turn_teardown = function(...) list(n_tokens = 1L))
  sent <- NULL
  chat <- list(stream_async = function(...) {
    sent <<- list(...)[[1]]
    coro::async_generator(function() coro::yield(ellmer::ContentText("ok")))()
  })
  reg <- ups_registry(function(message)
    list(action = "add_context", additional_context = "SCOPE: s2-2"))
  client <- structure(list(chat = chat, settings = list(hooks_registry = reg)),
                      class = "CodeagentClient")
  res <- ups_settle(codeagent_stream_async(client, "plot it", iteration = 2L,
                                           cwd = tempdir()))
  expect_identical(res$text, "ok")
  expect_match(sent, "^plot it\n\n")
  expect_match(sent, "SCOPE: s2-2$")
})

test_that("codeagent_stream_async ends the turn when a hook blocks", {
  called <- FALSE
  chat <- list(stream_async = function(...) { called <<- TRUE; stop("must not run") })
  reg <- ups_registry(function(message) list(action = "block", message = "blocked: policy"))
  client <- structure(list(chat = chat, settings = list(hooks_registry = reg)),
                      class = "CodeagentClient")
  shown <- NULL
  res <- ups_settle(codeagent_stream_async(client, "x", on_delta = function(t) shown <<- t))
  expect_false(called)
  expect_identical(res$stop_reason, "hook_blocked")
  expect_identical(shown, "blocked: policy")
})

test_that("the Shiny chat runs UserPromptSubmit before the Data Shield gate", {
  src <- paste(deparse(body(server_chat)), collapse = "\n")
  ups_at  <- regexpr(".run_user_prompt_submit(settings, text_part)", src, fixed = TRUE)
  gate_at <- regexpr(".input_gate_guarded(actual_input", src, fixed = TRUE)
  expect_gt(ups_at, 0L)
  expect_gt(gate_at, ups_at)
  expect_match(src, "additional_context = ups$additional_context", fixed = TRUE)
})
