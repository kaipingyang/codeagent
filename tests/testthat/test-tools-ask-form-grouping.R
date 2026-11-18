# AskUserForm field type "grouping": every choice (e.g. a treatment arm) gets
# a group name the user can edit; the result maps group -> its choices.

arms <- c("A 10mg", "A 20mg", "A+B 10mg", "A+B 20mg")

test_that("a grouping field needs choices; its default presets the groups", {
  spec <- .form_validate_fields(list(list(name = "groups", type = "grouping", choices = arms,
                                          default = "Mono: A 10mg, A 20mg; Combo: A+B 10mg, A+B 20mg")))
  expect_identical(spec[[1]]$type, "grouping")
  expect_match(.form_validate_fields(list(list(name = "g", type = "grouping"))), "needs `choices`")
  expect_identical(.grouping_preset(spec[[1]]$default, arms), c("Mono", "Mono", "Combo", "Combo"))
  expect_identical(.grouping_preset("", arms), arms)   # no default: every choice its own group
})

test_that("grouping values: group -> choices; a blank group keeps the choice on its own", {
  f <- list(name = "groups", label = "Groups", type = "grouping", choices = arms, default = "", required = TRUE, help = "")
  v <- .form_coerce(f, c("Mono", "Mono", "", "Combo 20"))
  expect_identical(v, list(Mono = c("A 10mg", "A 20mg"), `A+B 10mg` = "A+B 10mg", `Combo 20` = "A+B 20mg"))
  # the CLI / test path gives the text form
  expect_identical(.form_coerce(f, "Low: A 10mg, A+B 10mg; High: A 20mg, A+B 20mg"),
                   list(Low = c("A 10mg", "A+B 10mg"), High = c("A 20mg", "A+B 20mg")))
})

test_that("a grouping field renders one group box per choice", {
  f <- .form_validate_fields(list(list(name = "groups", type = "grouping", choices = arms,
                                       default = "Mono: A 10mg, A 20mg")))[[1]]
  html <- as.character(.form_field_input(f, 1))
  expect_match(html, "ca_form_1_g4", fixed = TRUE)
  expect_match(html, "value=\"Mono\"", fixed = TRUE)
  expect_match(html, "A+B 20mg", fixed = TRUE)
})

test_that("Shiny: a submitted grouping form resolves with the groups", {
  testthat::local_mocked_bindings(chat_append_message = function(...) invisible(NULL), .package = "shinychat")
  captured <- new.env(); captured$ans <- NULL
  spec <- .form_validate_fields(list(list(name = "groups", type = "grouping", choices = arms)))
  shiny::testServer(function(input, output, session) {
    state <- shiny::reactiveValues(pending_interaction = NULL)
    server_interaction(input, output, session, state)
    session$userData$state <- state
  }, {
    session$userData$state$pending_interaction <- list(
      type = "form", payload = list(title = "t", fields = spec), resolve = function(v) captured$ans <- v)
    session$flushReact()
    session$setInputs(ca_form_1_g1 = "Mono", ca_form_1_g2 = "Mono", ca_form_1_g3 = "Combo",
                      ca_form_1_g4 = "Combo", ca_form_submit = 1)
  })
  expect_true(captured$ans$submitted)
  expect_identical(captured$ans$values$groups, list(Mono = c("A 10mg", "A 20mg"), Combo = c("A+B 10mg", "A+B 20mg")))
})
