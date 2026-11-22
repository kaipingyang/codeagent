# AskUserQuestion with several questions (1-4), option descriptions,
# multiSelect and an "Other" answer -- the public Claude Code interface.
# The single `question` / `choices` form keeps working.

qs_example <- list(
  list(question = "Which population?", header = "Population",
       options = list(list(label = "Safety Analysis Set", description = "All treated"),
                      list(label = "Efficacy Evaluable Set")),
       multiSelect = FALSE),
  list(question = "Which statistics?", header = "Stats",
       options = list(list(label = "n"), list(label = "Mean (SD)"), list(label = "Median")),
       multiSelect = TRUE))

test_that("ask_user_tool offers `questions` next to the single question", {
  t <- ask_user_tool()
  expect_true(all(c("question", "choices", "questions") %in% names(t@arguments@properties)))
  expect_false(t@arguments@properties$question@required)
  expect_match(t@description, "multiSelect", fixed = TRUE)
  expect_match(t@description, "Other", fixed = TRUE)
})

test_that(".normalize_questions accepts lists and the data frames ellmer may pass", {
  q <- .normalize_questions(qs_example)
  expect_length(q, 2L)
  expect_identical(q[[1]]$options[[1]]$description, "All treated")
  expect_identical(q[[2]]$multiSelect, TRUE)
  df <- data.frame(question = c("A?", "B?"), header = c("a", "b"), multiSelect = c(FALSE, TRUE))
  df$options <- list(data.frame(label = c("x", "y")), data.frame(label = c("u", "v"), description = c("U", "V")))
  q2 <- .normalize_questions(df)
  expect_identical(vapply(q2, `[[`, "", "question"), c("A?", "B?"))
  expect_identical(q2[[2]]$options[[2]]$description, "V")
  expect_error(.normalize_questions(rep(qs_example, 3)), "1 to 4")
  expect_error(.normalize_questions(list(list(question = "Q", options = list(list(label = "only"))))), "at least 2")
  expect_error(.normalize_questions(list(list(question = "", options = qs_example[[1]]$options))), "question")
})

test_that("answers come back to the model per question", {
  q <- .normalize_questions(qs_example)
  txt <- .questions_answer_text(q, list("Safety Analysis Set", c("n", "Median")))
  expect_match(txt, "\"Which population?\"=\"Safety Analysis Set\"", fixed = TRUE)
  expect_match(txt, "\"Which statistics?\"=\"n, Median\"", fixed = TRUE)
  expect_match(.questions_answer_text(q, NULL), "dismissed", fixed = TRUE)
})

test_that("CLI / test path answers each question (option numbers or text)", {
  withr::local_options(codeagent.test_ask_answer = c("2", "1,3"))
  res <- .ask_user_impl(NULL, NULL, NULL, questions = .normalize_questions(qs_example))
  expect_match(res@value, "\"Which population?\"=\"Efficacy Evaluable Set\"", fixed = TRUE)
  expect_match(res@value, "\"Which statistics?\"=\"n, Median\"", fixed = TRUE)
  withr::local_options(codeagent.test_ask_answer = "my own")
  res <- .ask_user_impl(NULL, NULL, NULL, questions = .normalize_questions(qs_example[1]))
  expect_match(res@value, "\"Which population?\"=\"my own\"", fixed = TRUE)   # "Other"
})

test_that("Shiny: questions are queued as one interaction and rendered as a paged card", {
  state <- shiny::reactiveValues(pending_interaction = NULL)
  aqf <- .shiny_ask_question_fn(session = NULL, state = state)
  shiny::isolate(aqf(NULL, NULL, questions = .normalize_questions(qs_example)))
  p <- shiny::isolate(state$pending_interaction)
  expect_identical(p$type, "questions")
  html <- as.character(.interaction_bar_ui(p))
  expect_match(html, "Population", fixed = TRUE)                 # eyebrow
  expect_match(html, "All treated", fixed = TRUE)                # description
  expect_match(html, 'class="ca-q-num" aria-hidden="true">1<', fixed = TRUE)
  expect_match(html, 'data-multi="true"', fixed = TRUE)         # multiSelect page
  expect_match(html, "ca-q-check", fixed = TRUE)
  expect_match(html, "1 / 2", fixed = TRUE)
  expect_match(html, ">Next<", fixed = TRUE)
  expect_identical(lengths(regmatches(html, gregexpr("ca-q-page\"", html))), 2L)
  expect_match(html, 'data-i="2"[^>]*hidden')                  # one page at a time
})

test_that("recommended options are pre-selected the DSH way", {
  qs <- list(
    list(question = "Q1", header = "", multiSelect = FALSE,
         options = list(list(label = "A (Recommended)"), list(label = "B"))),
    list(question = "Q2", header = "", multiSelect = TRUE,
         options = list(list(label = "x"), list(label = "y (recommended)"), list(label = "z (Recommended)"))))
  html <- as.character(.question_card_ui(qs))
  sel <- regmatches(html, gregexpr('is-selected" role="[a-z]+" aria-checked="true" data-label="[^"]+"', html))[[1]]
  expect_identical(sub(".*data-label=\"([^\"]+)\"", "\\1", sel), c("A (Recommended)", "y (recommended)", "z (Recommended)"))
  expect_false(grepl(">A (Recommended)<", html, fixed = TRUE))   # suffix not shown
})

test_that("Shiny: the card's answers resolve the request and leave a record in the reply", {
  posted <- new.env(); posted$msg <- NULL
  testthat::local_mocked_bindings(chat_append_message = function(id, msg, ...) posted$msg <- msg, .package = "shinychat")
  captured <- new.env()
  shiny::testServer(function(input, output, session) {
    state <- shiny::reactiveValues(pending_interaction = NULL)
    server_interaction(input, output, session, state)
    session$userData$state <- state
  }, {
    st <- session$userData$state
    st$pending_interaction <- list(type = "questions",
      payload = list(questions = .normalize_questions(qs_example)),
      resolve = function(v) captured$ans <- v)
    session$flushReact()
    session$setInputs(ca_q_answers = list(nonce = 1, answers = list(
      list(selected = list("Safety Analysis Set"), custom = "", skipped = FALSE),
      list(selected = list("n", "Median"), custom = "Min", skipped = FALSE))))
    expect_identical(captured$ans, list("Safety Analysis Set", c("n", "Median", "Min")))
    expect_match(posted$msg$content, "Answered: Which population?", fixed = TRUE)
    expect_match(posted$msg$content, "n, Median, Min", fixed = TRUE)

    st$pending_interaction <- list(type = "questions",
      payload = list(questions = .normalize_questions(qs_example)),
      resolve = function(v) captured$ans <- v)
    session$setInputs(ca_q_answers = list(nonce = 2, answers = list(
      list(selected = list("Safety Analysis Set"), custom = "own set", skipped = FALSE),
      list(selected = list(), custom = "", skipped = TRUE))))
    expect_identical(captured$ans, list("own set", character()))

    st$pending_interaction <- list(type = "questions",
      payload = list(questions = .normalize_questions(qs_example)),
      resolve = function(v) captured$ans <- v)
    session$setInputs(ca_q_answers = list(nonce = 3, dismissed = TRUE))
    expect_identical(captured$ans, list())                       # dismissed

    st$pending_interaction <- list(type = "question",
      payload = list(question = "Pick", choices = c("a", "b")),
      resolve = function(v) captured$ans <- v)
    session$setInputs(ca_q_answers = list(nonce = 4, answers = list(
      list(selected = list("b"), custom = "", skipped = FALSE))))
    expect_identical(captured$ans, "b")
    session$setInputs(ca_q_answers = list(nonce = 5, answers = list()))   # nothing pending: ignored
    expect_identical(captured$ans, "b")
  })
})

test_that("Shiny: Submit resolves with one answer per question, Other text replaces the choice", {
  testthat::local_mocked_bindings(chat_append_message = function(...) invisible(NULL), .package = "shinychat")
  captured <- new.env(); captured$ans <- NULL
  shiny::testServer(function(input, output, session) {
    state <- shiny::reactiveValues(pending_interaction = NULL)
    server_interaction(input, output, session, state)
    session$userData$state <- state
  }, {
    session$userData$state$pending_interaction <- list(
      type = "questions", payload = list(questions = .normalize_questions(qs_example)),
      resolve = function(v) captured$ans <- v)
    session$flushReact()
    session$setInputs(ca_qs_1 = "__other__", ca_qs_other_1 = "Per-protocol set",
                      ca_qs_2 = c("n", "Median"), ca_q_submit = 1)
    expect_null(shiny::isolate(session$userData$state$pending_interaction))
    expect_identical(captured$ans, list("Per-protocol set", c("n", "Median")))
  })
  expect_identical(.interaction_cancel_value(list(type = "questions")), list())
})
