test_that("codeagent_ask_form asks through the session's form card and returns its answer", {
  asked <- NULL
  session <- shiny::MockShinySession$new()
  session$userData$codeagent_ask_form_fn <- function(title, fields, submit_label) {
    asked <<- list(title = title, fields = fields, submit_label = submit_label)
    promises::promise_resolve(list(submitted = TRUE, values = list(arms = list(Mono = c("a", "b")))))
  }
  p <- codeagent_ask_form("Combine treatment groups",
    list(list(name = "arms", label = "Groups", type = "grouping", choices = c("a", "b", "c"),
              default = "Mono: a, b")), submit_label = "Use these groups", session = session)
  expect_s3_class(p, "promise")
  out <- NULL
  promises::then(p, function(v) out <<- v)
  for (i in 1:10) later::run_now(0.01)
  expect_true(out$submitted)
  expect_identical(out$values$arms$Mono, c("a", "b"))
  expect_identical(asked$fields[[1]]$type, "grouping")          # validated spec, choices kept
  expect_identical(asked$fields[[1]]$choices, c("a", "b", "c"))
  expect_identical(asked$submit_label, "Use these groups")
})

test_that("a cancelled host form has no values; a bad spec is an error", {
  session <- shiny::MockShinySession$new()
  session$userData$codeagent_ask_form_fn <- function(...) promises::promise_resolve(list(submitted = FALSE))
  out <- NULL
  promises::then(codeagent_ask_form("t", list(list(name = "x", type = "text")), session = session),
                 function(v) out <<- v)
  for (i in 1:10) later::run_now(0.01)
  expect_false(out$submitted)
  expect_length(out$values, 0L)
  expect_error(codeagent_ask_form("t", list(list(name = "g", type = "grouping")), session = session), "needs `choices`")
  expect_error(codeagent_ask_form("t", list(), session = session), "non-empty")
})

test_that("without a codeagent session the form is answered from the test option", {
  withr::local_options(codeagent.test_form_answer = list(g = "Mono: a; Combo: b, c"))
  out <- codeagent_ask_form("t", list(list(name = "g", type = "grouping", choices = c("a", "b", "c"))), session = NULL)
  expect_true(out$submitted)
  expect_identical(out$values$g$Combo, c("b", "c"))
  withr::local_options(codeagent.test_form_answer = FALSE)
  expect_false(codeagent_ask_form("t", list(list(name = "x", type = "text")), session = NULL)$submitted)
})

test_that("codeagent_server gives host tools the session's form function", {
  f <- test_path("..", "..", "R", "embed.R")
  skip_if_not(file.exists(f), "package sources not available")
  embed <- paste(readLines(f), collapse = "\n")
  expect_match(embed, "session$userData$codeagent_ask_form_fn <- interaction$ask_form_fn", fixed = TRUE)
})
