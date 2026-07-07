# Deterministic integration coverage for the async paths that unit tests miss
# (the class of bug the live permission-gate e2e caught): the AskUserQuestion
# pause/resolve flow, and singleton registration of on_tool_result callbacks
# (mid-loop compaction) under the Shiny multi-registration pattern.

test_that("AskUserQuestion: ask_question_fn stores a pending question", {
  state <- shiny::reactiveValues(pending_interaction = NULL)
  aqf   <- .shiny_ask_question_fn(session = NULL, state = state)
  shiny::isolate(aqf("Pick one", choices = c("x", "y")))
  p <- shiny::isolate(state$pending_interaction)
  expect_identical(p$type, "question")
  expect_identical(p$payload$question, "Pick one")
  expect_identical(p$payload$choices, c("x", "y"))
})

test_that("AskUserQuestion: Submit observer resolves the pending question with the answer", {
  skip_if_not_installed("shiny")
  testthat::local_mocked_bindings(
    chat_append_message = function(...) invisible(NULL), .package = "shinychat")
  captured <- new.env(); captured$ans <- NA_character_

  shiny::testServer(function(input, output, session) {
    state <- shiny::reactiveValues(pending_interaction = NULL)
    server_interaction(input, output, session, state)
    session$userData$state <- state
  }, {
    session$userData$state$pending_interaction <- list(
      type = "question", payload = list(question = "Q", choices = c("x", "y")),
      resolve = function(v) captured$ans <- v)
    session$flushReact()
    session$setInputs(ca_q_choice = "y", ca_q_submit = 1)
    expect_null(shiny::isolate(session$userData$state$pending_interaction))  # cleared
    expect_identical(captured$ans, "y")                                     # resolved w/ answer
  })
})

test_that("AskUserQuestion: ESC cancels a pending question with empty answer", {
  skip_if_not_installed("shiny")
  testthat::local_mocked_bindings(
    chat_append_message = function(...) invisible(NULL), .package = "shinychat")
  captured <- new.env(); captured$ans <- "unset"

  shiny::testServer(function(input, output, session) {
    state <- shiny::reactiveValues(pending_interaction = NULL)
    server_interaction(input, output, session, state)
    session$userData$state <- state
  }, {
    session$userData$state$pending_interaction <- list(
      type = "question", payload = list(question = "Q"),
      resolve = function(v) captured$ans <- v)
    session$flushReact()
    session$setInputs(esc = 1)
    expect_null(shiny::isolate(session$userData$state$pending_interaction))
    expect_identical(captured$ans, "")   # ESC on a question -> empty answer (no deadlock)
  })
})

test_that(".chat_once guards singleton callbacks per chat+key", {
  chat <- ellmer::chat_openai_compatible(
    base_url = "http://x", model = "m", credentials = function() "k")
  expect_true(.chat_once(chat, "k1"))    # first time for this chat+key
  expect_false(.chat_once(chat, "k1"))   # subsequent -> guarded
  expect_true(.chat_once(chat, "k2"))    # different key is independent
})

test_that("register_midloop_compaction installs its on_tool_result callback only once", {
  chat <- ellmer::chat_openai_compatible(
    base_url = "http://x", model = "m", credentials = function() "k")
  # Simulate the Shiny multi-registration: called several times on the same chat.
  expect_invisible(register_midloop_compaction(chat, list(midloop_compact = TRUE)))
  expect_invisible(register_midloop_compaction(chat, list(midloop_compact = TRUE)))
  expect_invisible(register_midloop_compaction(chat, list(midloop_compact = TRUE)))
  # After the first install, .chat_once has consumed the "midloop" slot for this chat.
  expect_false(.chat_once(chat, "midloop"))
})
