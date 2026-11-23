# AskUserForm field type "grouping": rows of an editable group name and a
# checklist of the choices (e.g. treatment arms), "+ Add group"; a choice is
# in one group at most; the result maps group -> its choices.

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

test_that("a grouping field renders one row per preset group, a row template and Add group", {
  f <- .form_validate_fields(list(list(name = "groups", type = "grouping", choices = arms,
                                       default = "Mono: A 10mg, A 20mg; Combo: A+B 10mg")))[[1]]
  html <- as.character(.form_field_input(f, 1))
  expect_match(html, 'data-input="ca_form_1"', fixed = TRUE)
  expect_match(html, 'value="Mono"', fixed = TRUE); expect_match(html, 'value="Combo"', fixed = TRUE)
  expect_identical(lengths(regmatches(html, gregexpr('class="ca-grp-row"', html, fixed = TRUE))), 3L)   # 2 rows + template
  expect_match(html, "+ Add group", fixed = TRUE)
  expect_match(html, 'value="A 10mg" checked', fixed = TRUE)
  # no default: one empty "Group 1" row
  g <- .form_validate_fields(list(list(name = "g", type = "grouping", choices = arms)))[[1]]
  expect_match(as.character(.form_field_input(g, 1)), 'value="Group 1"', fixed = TRUE)
})

test_that("submitted rows: first row wins a choice, empty rows dropped, the rest stay on their own", {
  rows <- '[{"name":"Mono","items":["A 10mg","A 20mg"]},{"name":"Combo","items":["A 20mg","A+B 10mg"]},{"name":"","items":["A+B 20mg"]},{"name":"Empty","items":[]}]'
  expect_identical(.grouping_rows_value(rows, arms),
                   list(Mono = c("A 10mg", "A 20mg"), Combo = "A+B 10mg", `A+B 20mg` = "A+B 20mg"))
  expect_identical(.grouping_rows_preset("Mono: A 10mg; Again: A 10mg, A 20mg", arms),
                   list(list(name = "Mono", items = "A 10mg"), list(name = "Again", items = "A 20mg")))
  expect_identical(.grouping_rows_value("Low: A 10mg", arms), "Low: A 10mg")   # not JSON: the text form
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
    session$setInputs(ca_form_1 = '[{"name":"Mono","items":["A 10mg","A 20mg"]},{"name":"Combo","items":["A+B 10mg","A+B 20mg"]}]',
                      ca_form_submit = 1)
  })
  expect_true(captured$ans$submitted)
  expect_identical(captured$ans$values$groups, list(Mono = c("A 10mg", "A 20mg"), Combo = c("A+B 10mg", "A+B 20mg")))
})
