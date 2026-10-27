# Concurrent interactions (two approvals from parallel tool calls, a form
# while an approval is open, ...) are queued and shown one at a time; before,
# the second overwrote the single slot and the first tool waited forever.

test_that("a second request waits behind the shown one and every promise resolves", {
  state <- shiny::reactiveValues(pending_interaction = NULL)
  ask <- .shiny_ask_fn(NULL, state)
  form <- .shiny_ask_form_fn(NULL, state)
  got <- new.env()
  promises::then(ask("Write", list(file_path = "a")), function(v) got$approval <- v)
  promises::then(form("Confirm", list(list(name = "x"))), function(v) got$form <- v)
  for (i in 1:5) later::run_now(0.01)

  expect_identical(shiny::isolate(state$pending_interaction$type), "approval")
  expect_length(shiny::isolate(state$interaction_queue), 1L)

  expect_true(.resolve_pending(state, TRUE))
  for (i in 1:5) later::run_now(0.01)
  expect_identical(got$approval, TRUE)
  expect_identical(shiny::isolate(state$pending_interaction$type), "form")   # next one shown
  expect_null(shiny::isolate(state$interaction_queue))

  .resolve_pending(state, list(submitted = TRUE, values = list(x = "1")))
  for (i in 1:5) later::run_now(0.01)
  expect_true(got$form$submitted)
  expect_null(shiny::isolate(state$pending_interaction))
})

test_that("a queued request can be resolved by token (egress timeout) without touching the shown one", {
  state <- shiny::reactiveValues(pending_interaction = NULL)
  seen <- new.env()
  .enqueue_interaction(state, list(type = "approval", payload = list(), resolve = function(v) seen$a <- v))
  tok <- .enqueue_interaction(state, list(type = "egress", payload = list(), resolve = function(v) seen$e <- v))
  expect_true(.resolve_interaction_token(state, tok, "redact"))
  expect_identical(seen$e, "redact")
  expect_null(seen$a)
  expect_identical(shiny::isolate(state$pending_interaction$type), "approval")
  expect_null(shiny::isolate(state$interaction_queue))
  expect_false(.resolve_interaction_token(state, tok, "redact"))   # already gone
})

test_that("clearing resolves every shown and queued request with its cancel value", {
  state <- shiny::reactiveValues(pending_interaction = NULL)
  seen <- new.env()
  .enqueue_interaction(state, list(type = "approval", payload = list(), resolve = function(v) seen$a <- v))
  .enqueue_interaction(state, list(type = "form", payload = list(), resolve = function(v) seen$f <- v))
  .enqueue_interaction(state, list(type = "question", payload = list(), resolve = function(v) seen$q <- v))
  .clear_interactions(state)
  expect_false(seen$a)
  expect_false(seen$f$submitted)
  expect_identical(seen$q, "")
  expect_null(shiny::isolate(state$pending_interaction))
  expect_null(shiny::isolate(state$interaction_queue))
})

test_that("the bar says how many requests are waiting", {
  skip_if_not_installed("shiny")
  shiny::testServer(function(input, output, session) {
    state <- shiny::reactiveValues(pending_interaction = NULL)
    server_interaction(input, output, session, state)
    session$userData$state <- state
  }, {
    st <- session$userData$state
    .enqueue_interaction(st, list(type = "approval", payload = list(tool_name = "A"), resolve = function(v) NULL))
    .enqueue_interaction(st, list(type = "approval", payload = list(tool_name = "B"), resolve = function(v) NULL))
    session$flushReact()
    html <- as.character(output$ca_interaction_ui$html)
    expect_match(html, "1 more request waiting", fixed = TRUE)
    expect_match(html, ">A<", fixed = TRUE)
  })
})
