# tests/testthat/test-form-widgets.R
# AskUserForm widgets: presets, mixing, priority, fallbacks; layout hints.

fld <- function(type, ...) {
  spec <- .form_validate_fields(list(list(name = "f", type = type, ...)))
  if (is.character(spec)) stop(spec)
  spec[[1]]
}
html_of <- function(widgets, type, ...) as.character(.form_field_input(fld(type, ...), 1L, widgets))

test_that("NULL is Shiny's own controls for every type", {
  w <- .form_widgets_resolve(NULL)
  expect_setequal(names(w), .FORM_WIDGET_TYPES)
  expect_match(html_of(w, "select", choices = list("a", "b")), "<select", fixed = TRUE)
  expect_match(html_of(w, "date"), "shiny-date-input", fixed = TRUE)
})

test_that("presets are tried in order per type; Shiny fills the rest", {
  skip_if_not_installed("shinyWidgets")
  skip_if_not_installed("shiny.element")
  w <- .form_widgets_resolve(c("shinyWidgets", "shiny.element"))
  expect_match(html_of(w, "select", choices = list("a")), "selectpicker", fixed = TRUE)   # shinyWidgets first
  expect_match(html_of(w, "text"), "el-input", fixed = TRUE)                              # only element has text
  w2 <- .form_widgets_resolve("shinyWidgets")
  expect_match(html_of(w2, "text"), "shiny-input-text form-control", fixed = TRUE)          # native
})

test_that("named entries override one type, from a function or a preset name", {
  skip_if_not_installed("shinyWidgets")
  skip_if_not_installed("shiny.element")
  mine <- function(id, label, value, choices, field) htmltools::tags$input(id = id, class = "mine")
  w <- .form_widgets_resolve(list("shiny.element", date = "shinyWidgets", checkbox = mine))
  expect_match(html_of(w, "date"), "sw-air-picker", fixed = TRUE)
  expect_match(html_of(w, "checkbox"), 'class="mine"', fixed = TRUE)
  expect_match(html_of(w, "number"), "el-input-number", fixed = TRUE)
  own <- list(select = mine, multiselect = mine)
  w3 <- .form_widgets_resolve(list(own, "shiny.element"))
  expect_match(html_of(w3, "select", choices = list("a")), 'class="mine"', fixed = TRUE)
})

test_that("bad specs fail early; a missing package falls through with a warning", {
  expect_error(.form_widgets_resolve("shiny.fluent"), "no preset")
  expect_error(.form_widgets_resolve(list(slider = function(...) NULL)), "unknown field type")
  expect_error(.form_widgets_resolve(list(date = 3)), "function or a preset")
  expect_error(.form_widgets_resolve(list(list(1))), "preset name or a named list")
  expect_error(.form_widgets_resolve(42), "must be NULL")
  testthat::local_mocked_bindings(requireNamespace = function(pkg, ...) !pkg %in% "shinyWidgets",
                                  .package = "base")
  expect_warning(w <- .form_widgets_resolve("shinyWidgets"), "not installed")
  expect_match(html_of(w, "select", choices = list("a")), "<select", fixed = TRUE)
})

test_that("every built-in preset builds every type it offers", {
  for (p in names(.FORM_PRESETS)) {
    if (!is.null(.FORM_PRESETS[[p]]$package)) skip_if_not_installed(.FORM_PRESETS[[p]]$package)
    w <- .form_widgets_resolve(p)
    for (t in .FORM_WIDGET_TYPES) {
      args <- list(t, label = "L", placeholder = "ph")
      if (t %in% c("select", "multiselect")) args$choices <- list("a", "b")
      if (t == "number") { args$min <- 0; args$max <- 9 }
      expect_no_error(h <- do.call(html_of, c(list(w), args)))
      expect_match(h, "ca_form_1", fixed = TRUE, info = paste(p, t))
    }
  }
})

test_that("sections are headings over auto-fitting grids; long fields span the row", {
  spec <- .form_validate_fields(list(
    list(name = "a", type = "number", section = "Display"),
    list(name = "b", type = "date", width = "half", section = "Display"),   # old hint: auto
    list(name = "c", type = "textarea", section = "Notes"),
    list(name = "d", type = "text", width = "full", section = "Notes"),
    list(name = "e", type = "text")))
  expect_identical(spec[[2]]$width, "auto")
  html <- as.character(.form_fields_ui(spec))
  count <- function(p) lengths(regmatches(html, gregexpr(p, html, fixed = TRUE)))
  expect_identical(count("ca-form-section"), 2L)
  expect_identical(count('class="ca-form-grid"'), 3L)
  expect_identical(count("ca-form-cell ca-form-cell--wide"), 2L)          # textarea + full
  expect_match(.form_validate_fields(list(list(name = "f", type = "text", width = "third"))), "auto")
})

test_that("field attributes are validated with messages the model can act on", {
  v <- function(...) .form_validate_fields(list(list(name = "f", ...)))
  expect_match(v(type = "number", min = 5, max = 1), "larger than")
  expect_match(v(type = "number", step = 0), "positive")
  expect_match(v(type = "text", width = "third"), "width")
  expect_match(v(type = "text", pattern = "(a+)+$"), "nest")
  expect_match(v(type = "text", pattern = "(a)\\1"), "backreferences")
  expect_match(v(type = "text", pattern = "[a-"), "not a valid")
  ok <- v(type = "text", pattern = "^[A-Z]{3}$", pattern_hint = "three capitals", placeholder = "ABC")
  expect_identical(ok[[1]]$pattern, "^[A-Z]{3}$")
  expect_identical(ok[[1]]$placeholder, "ABC")
})

test_that("collection reports values outside the limits", {
  spec <- .form_validate_fields(list(
    list(name = "n", label = "Decimals", type = "number", min = 0, max = 4),
    list(name = "code", label = "Code", type = "text", pattern = "^[A-Z]{3}$", pattern_hint = "three capitals"),
    list(name = "pop", label = "Pop", type = "select", choices = list("A", "B")),
    list(name = "own", label = "Own", type = "select", choices = list("A"), allow_other = TRUE)))
  bad <- .form_collect(spec, list(n = 7, code = "ab", pop = "Z", own = "mine"))
  expect_identical(bad$invalid, c("Decimals: at most 4", "Code: three capitals", "Pop: choose from the list"))
  good <- .form_collect(spec, list(n = 2, code = "ABC", pop = "A", own = "mine"))
  expect_length(good$invalid, 0L)
  expect_identical(good$values$own, "mine")
})

test_that("a refused submit says why in the form and marks the fields", {
  sent <- list()
  testthat::local_mocked_bindings(.send_form_feedback = function(session, msg)
    sent[[length(sent) + 1L]] <<- list(type = "ca_form_feedback", msg = msg))
  shiny::testServer(function(input, output, session) {
    state <- shiny::reactiveValues(pending_interaction = NULL, interaction_queue = NULL)
    server_interaction(input, output, session, state)
    session$userData$state <- state
  }, {
    spec <- .form_validate_fields(list(
      list(name = "t", label = "Title", type = "text", required = TRUE),
      list(name = "n", label = "Decimals", type = "number", max = 4)))
    resolved <- NULL
    session$userData$state$pending_interaction <- list(type = "form",
      payload = list(title = "T", fields = spec), resolve = function(v) resolved <<- v)
    session$flushReact()
    session$setInputs(ca_form_1 = "", ca_form_2 = 9, ca_form_submit = 1)
    fb <- Filter(function(s) identical(s$type, "ca_form_feedback"), sent)
    expect_length(fb, 1L)
    expect_match(fb[[1]]$msg$message, "Please fill in: Title", fixed = TRUE)
    expect_match(fb[[1]]$msg$message, "Decimals: at most 4", fixed = TRUE)
    expect_identical(unlist(fb[[1]]$msg$fields), c(1L, 2L))
    expect_null(resolved)
  })
  html <- as.character(.interaction_bar_ui(list(type = "form",
    payload = list(title = "T", fields = .form_validate_fields(list(list(name = "a", type = "text")))))))
  expect_match(html, 'class="ca-form-feedback"', fixed = TRUE)
  expect_match(html, 'data-i="1"', fixed = TRUE)
})
