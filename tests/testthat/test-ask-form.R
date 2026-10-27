# AskUserForm: field validation, value collection, CLI/test path, Shiny bar.

form_fields <- list(
  list(name = "population", label = "Population", type = "select",
       choices = list("Safety", "ITT"), default = "Safety", required = TRUE),
  list(name = "vars", type = "multiselect", choices = list("AGE", "SEX", "RACE"),
       default = "AGE,SEX"),
  list(name = "total", label = "Add total", type = "checkbox", default = "true"),
  list(name = "conf", type = "number", default = "0.95"),
  list(name = "note", type = "text")
)

test_that("field specs are normalised with defaults", {
  spec <- .form_validate_fields(form_fields)
  expect_length(spec, 5L)
  expect_identical(spec[[1]]$label, "Population")
  expect_identical(spec[[2]]$label, "vars")          # label defaults to name
  expect_identical(spec[[2]]$choices, c("AGE", "SEX", "RACE"))
  expect_true(spec[[1]]$required)
  expect_false(spec[[5]]$required)
  expect_identical(spec[[5]]$default, "")
})

test_that("invalid field specs return a message the model can act on", {
  expect_match(.form_validate_fields(list()), "non-empty")
  expect_match(.form_validate_fields(list(list(name = "1x", type = "text"))), "must start with a letter")
  expect_match(.form_validate_fields(list(list(name = "a", type = "slider"))), "unknown type")
  expect_match(.form_validate_fields(list(list(name = "a", type = "select"))), "needs `choices`")
  expect_match(.form_validate_fields(list(list(name = "a"), list(name = "a"))), "unique")
  too_many <- lapply(seq_len(21), function(i) list(name = paste0("f", i)))
  expect_match(.form_validate_fields(too_many), "at most")
})

test_that("submitted values are coerced per type and required fields are checked", {
  spec <- .form_validate_fields(form_fields)
  got <- .form_collect(spec, list(population = "ITT", vars = c("AGE", "RACE"),
                                  total = FALSE, conf = "0.9", note = "hi"))
  expect_length(got$missing, 0L)
  expect_identical(got$values$population, "ITT")
  expect_identical(got$values$vars, c("AGE", "RACE"))
  expect_false(got$values$total)
  expect_equal(got$values$conf, 0.9)
  expect_identical(.form_collect(spec, list(vars = "AGE, SEX"))$values$vars, c("AGE", "SEX"))
  expect_identical(.form_collect(spec, list(population = ""))$missing, "Population")
})

test_that("the sync tool answers from codeagent.test_form_answer and reports cancel", {
  tool <- ask_user_form_tool()
  withr::local_options(codeagent.test_form_answer = list(population = "ITT", conf = "0.8"))
  res <- S7::S7_data(tool)(title = "Confirm", fields = form_fields)
  out <- jsonlite::fromJSON(as.character(res@value))
  expect_true(out$submitted)
  expect_identical(out$values$population, "ITT")
  expect_equal(out$values$conf, 0.8)

  withr::local_options(codeagent.test_form_answer = FALSE)
  res <- S7::S7_data(tool)(title = "Confirm", fields = form_fields)
  expect_false(jsonlite::fromJSON(as.character(res@value))$submitted)
})

test_that("an invalid form comes back as a tool error, not a crash", {
  res <- S7::S7_data(ask_user_form_tool())(title = "x", fields = list(list(name = "a", type = "select")))
  expect_identical(res@extra$codeagent$artifact$kind, "error")
  expect_match(as.character(res@value), "needs `choices`")
})

test_that("the interaction bar renders one input per field plus submit / cancel", {
  spec <- .form_validate_fields(form_fields)
  html <- as.character(.interaction_bar_ui(list(
    type = "form", payload = list(title = "Confirm TFL", fields = spec, submit_label = "Run"))))
  for (i in seq_along(spec)) expect_match(html, sprintf('id="ca_form_%d"', i))
  expect_match(html, "ca_form_submit")
  expect_match(html, "ca_form_cancel")
  expect_match(html, "Confirm TFL")
  expect_match(html, ">Run<")
  expect_identical(.interaction_cancel_value(list(type = "form")), list(submitted = FALSE))
})

test_that("Shiny: submit resolves the form; a missing required field keeps it open", {
  shiny::testServer(function(input, output, session) {
    state <- shiny::reactiveValues(pending_interaction = NULL)
    session$userData$state <- state
    session$userData$fns <- server_interaction(input, output, session, state)
  }, {
    state <- session$userData$state
    answer <- NULL
    spec <- .form_validate_fields(form_fields)
    p <- session$userData$fns$ask_form_fn("Confirm", spec, "Run")
    promises::then(p, function(v) answer <<- v)
    session$flushReact()
    expect_identical(shiny::isolate(state$pending_interaction$type), "form")

    session$setInputs(ca_form_1 = "", ca_form_submit = 1)    # required left empty
    expect_false(is.null(shiny::isolate(state$pending_interaction)))

    session$setInputs(ca_form_1 = "ITT", ca_form_2 = c("SEX"), ca_form_3 = TRUE,
                      ca_form_4 = 0.9, ca_form_5 = "ok", ca_form_submit = 2)
    later::run_now()
    expect_null(shiny::isolate(state$pending_interaction))
    expect_true(answer$submitted)
    expect_identical(answer$values$population, "ITT")
    expect_identical(answer$values$vars, "SEX")
    expect_equal(answer$values$conf, 0.9)
  })
})

test_that("AskUserForm is registered with read capability in the interact group", {
  expect_true("AskUserForm" %in% .CODEAGENT_GROUPS$interact)
  expect_true("AskUserForm" %in% .READONLY_TOOLS)
})

test_that("fields as ellmer delivers them (tibble, NA for omitted attributes) render cleanly", {
  tool <- ask_user_form_tool()
  args <- list(title = "T", fields = list(
    list(name = "a", type = "text"),
    list(name = "b", type = "select", choices = list("x", "y"), label = "B", required = TRUE)))
  conv <- ellmer:::convert_from_type(args, tool@arguments)
  expect_s3_class(conv$fields, "data.frame")
  spec <- .form_validate_fields(conv$fields)
  expect_identical(spec[[1]]$label, "a")
  expect_identical(spec[[1]]$help, "")
  expect_identical(spec[[1]]$default, "")
  expect_false(spec[[1]]$required)
  expect_identical(spec[[2]]$choices, c("x", "y"))
  expect_true(spec[[2]]$required)
  html <- as.character(.interaction_bar_ui(list(type = "form",
    payload = list(title = "T", fields = spec, submit_label = "Go"))))
  expect_false(grepl(">NA<", html, fixed = TRUE))
  expect_identical(.form_collect(spec, list(a = "", b = ""))$missing, "B")
})

test_that("the async variant without a Shiny callback uses the test / CLI path", {
  withr::local_options(codeagent.test_form_answer = list(a = "v"))
  res <- S7::S7_data(ask_user_form_tool(async = TRUE))(title = "T", fields = list(list(name = "a")))
  done <- NULL
  promises::then(res, function(v) done <<- v)
  later::run_now(1)
  expect_identical(jsonlite::fromJSON(as.character(done@value))$values$a, "v")
})
