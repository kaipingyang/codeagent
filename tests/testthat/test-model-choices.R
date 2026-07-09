.mc_tmpdir <- function() {
  d <- file.path(tempdir(), paste0("mc", as.integer(stats::runif(1, 1, 1e7))))
  dir.create(d, showWarnings = FALSE)
  d
}

test_that(".config_model_choices reads client aliases from codeagent.md", {
  d <- .mc_tmpdir(); on.exit(unlink(d, recursive = TRUE), add = TRUE)
  writeLines(c(
    "---", "client:",
    "  a: openai/model-a", "  b: openai/model-b",
    "permission_mode: bypass", "btw_groups: [docs, env]",
    "---", "some system prompt body"
  ), file.path(d, "codeagent.md"))
  ch <- .config_model_choices(d, cur_model = "model-a")
  expect_type(ch, "character")
  expect_true(all(c("a", "b") %in% names(ch)))
  expect_true("openai/model-a" %in% ch)
  expect_true("openai/model-b" %in% ch)
})

test_that(".config_model_choices returns just the current model when no config", {
  d <- .mc_tmpdir(); on.exit(unlink(d, recursive = TRUE), add = TRUE)
  ch <- .config_model_choices(d, cur_model = "solo-model")
  expect_equal(unname(ch), "solo-model")
  expect_equal(names(ch), "solo-model")
})

test_that(".config_model_choices never yields NA/empty names (selectInput-safe)", {
  # Regression: unlisting the whole config (not just $client_spec) produced NA
  # names -> shiny::selectInput crashed with 'NAs are not allowed in ...'.
  d <- .mc_tmpdir(); on.exit(unlink(d, recursive = TRUE), add = TRUE)
  writeLines(c(
    "---", "client:", "  x: openai/mx",
    "btw_groups: [docs]", "permission_mode: bypass", "max_turns: 40",
    "---", "a multi-word system prompt body that would unlist badly"
  ), file.path(d, "codeagent.md"))
  ch <- .config_model_choices(d, cur_model = "mcur")
  expect_false(anyNA(names(ch)))
  expect_true(all(nzchar(names(ch))))
  expect_silent(shiny::selectInput("m", NULL, choices = ch))
})

test_that(".config_selected_model always yields a value present in choices", {
  ch <- c(gpt54 = "openai/gsds-gpt-54", gpt55 = "openai/gsds-gpt-55")
  # model-component match -> the matching spec value
  expect_equal(.config_selected_model(ch, "gsds-gpt-55"), "openai/gsds-gpt-55")
  # exact value match
  expect_equal(.config_selected_model(ch, "openai/gsds-gpt-54"), "openai/gsds-gpt-54")
  # no match -> falls back to first choice (still valid for selectInput)
  expect_true(.config_selected_model(ch, "nope") %in% ch)
  # single-model case (choice value == current model)
  ch2 <- c("gsds-gpt-54" = "gsds-gpt-54")
  expect_equal(.config_selected_model(ch2, "gsds-gpt-54"), "gsds-gpt-54")
  # the selected value is always in choices (the invariant selectInput needs)
  for (cm in c("gsds-gpt-55", "openai/gsds-gpt-54", "nope"))
    expect_true(.config_selected_model(ch, cm) %in% ch)
})
