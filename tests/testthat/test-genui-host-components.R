# Host-supplied canvas components and canvas options
# (references/plan/43-genui-data-and-extensions.md, section b).

toy_output_component <- function(name = "boxplot") {
  canvas_component_output(
    name = name,
    description = "Box plot of a numeric column by group.",
    args = list(y = ellmer::type_string("Numeric column."),
                by = ellmer::type_string("Grouping column.")),
    output = shiny::plotOutput,
    render = function(args, data) shiny::renderPlot(
      graphics::boxplot(stats::reformulate(args$by, args$y), data = data())))
}

toy_widget_component <- function(name = "summary_list") {
  canvas_component_widget(
    name = name,
    description = "A list of column names.",
    args = list(title = ellmer::type_string("Heading.", required = FALSE)),
    widget = function(args, data) htmltools::tags$ul(
      lapply(names(data), htmltools::tags$li)))
}

# -- canvas_options -------------------------------------------------------------

test_that("canvas_options() defaults keep today's behaviour", {
  o <- canvas_options()
  expect_s3_class(o, "codeagent_canvas_options")
  expect_true(o$starter)
  expect_length(o$components, 0L)
  expect_true(o$csp)
  expect_true(o$validate_text)
})

test_that("canvas_options() checks what it is given", {
  skip_if_no_genui()
  expect_error(canvas_options(components = list(1)), "genui_component")
  expect_error(canvas_options(starter = "no_such_component"), "no_such_component")
  expect_error(canvas_options(starter = NA), "starter")
  expect_error(canvas_options(csp = 1), "csp")
  expect_error(canvas_options(validate_text = "yes"), "validate_text")
  expect_error(canvas_options(components = list(toy_output_component("histogram"))),
               "histogram")
  expect_error(canvas_options(components = list(toy_output_component("refresh"))),
               "refresh")
  expect_error(canvas_options(components = list(toy_output_component("a"),
                                                toy_output_component("a"))),
               "more than once")
})

test_that("a host component may reuse a starter name the host left out", {
  skip_if_no_genui()
  o <- canvas_options(starter = c("data_table"),
                      components = list(toy_output_component("histogram")))
  expect_identical(o$starter, "data_table")
})

# -- component builders ----------------------------------------------------------

test_that("canvas_component_output() builds a genui_component around a Shiny output", {
  skip_if_no_genui()
  comp <- toy_output_component()
  expect_s3_class(comp, "genui_component")
  html <- as.character(comp$ui("m", list(y = "mpg", by = "cyl")))
  expect_match(html, 'id="m-out"', fixed = TRUE)
  expect_identical(.genui_output_ids(comp$ui("m", list())), "m-out")
  expect_true(.genui_needs_data(comp))
})

test_that("a canvas_component_output() server renders from the data it is given", {
  skip_if_no_genui()
  comp <- toy_output_component()
  session <- shiny::MockShinySession$new()
  shiny::withReactiveDomain(session,
    comp$server("m", list(y = "mpg", by = "cyl"), function() mtcars))
  out <- shiny::isolate(session$getOutput("m-out"))
  expect_match(out$src, "^data:image/png")
})

test_that("canvas_component_widget() renders any widget or tag through renderUI", {
  skip_if_no_genui()
  comp <- toy_widget_component()
  session <- shiny::MockShinySession$new()
  shiny::withReactiveDomain(session,
    comp$server("w", list(), function() mtcars))
  out <- shiny::isolate(session$getOutput("w-out"))
  expect_match(out$html, "<li>mpg</li>", fixed = TRUE)
})

test_that("a component's code template is kept for export", {
  skip_if_no_genui()
  comp <- canvas_component_output(
    "boxplot", "x", output = shiny::plotOutput,
    render = function(args, data) shiny::renderPlot(NULL),
    code = function(args, dataset) sprintf("boxplot(%s)", dataset))
  expect_identical(comp$code(list(), "cars"), "boxplot(cars)")
})

# -- catalog, tools and permissions -------------------------------------------------

test_that("the catalog holds the chosen starter components plus host components", {
  skip_if_no_genui()
  o <- canvas_options(starter = c("histogram", "card_row"),
                      components = list(toy_output_component(), toy_widget_component()))
  expect_setequal(names(.genui_build_catalog(o)),
                  c("histogram", "card_row", "boxplot", "summary_list"))
})

test_that("starter = FALSE leaves only host components and needs neither ggplot2 nor DT", {
  skip_if_no_genui()
  o <- canvas_options(starter = FALSE, components = list(toy_output_component()))
  expect_identical(names(.genui_build_catalog(o)), "boxplot")
  expect_false(any(c("ggplot2", "DT") %in% .genui_required_packages(o)))
  expect_true(all(c("ggplot2", "DT") %in% .genui_required_packages(canvas_options())))
})

test_that("no starter and no host components means no canvas", {
  local_mocked_bindings(.genui_available = function(...) TRUE)
  expect_false(.genui_wanted(list(tools_spec = NULL), per_session = TRUE,
                             options = canvas_options(starter = FALSE)))
})

test_that("passing canvas options asks for a canvas even on a shared client", {
  local_mocked_bindings(.genui_available = function(...) TRUE)
  expect_true(.genui_wanted(list(tools_spec = NULL), per_session = FALSE,
                            options = canvas_options(), explicit = TRUE))
  expect_false(.genui_wanted(list(tools_spec = NULL), per_session = FALSE,
                             options = canvas_options()))
})

test_that("an adapter offers one tool per catalog component, host ones included", {
  skip_if_no_genui()
  o <- canvas_options(starter = "histogram", components = list(toy_output_component()))
  a <- GenUIAdapter$new(data_env = genui_test_env(), options = o)
  tools <- a$tools()
  names(tools) <- vapply(tools, function(t) t@name, "")
  expect_true(all(c("canvas_histogram", "canvas_boxplot") %in% names(tools)))
  expect_false("canvas_scatter_plot" %in% names(tools))
  expect_setequal(names(tools$canvas_boxplot@arguments@properties),
                  c("dataset", "y", "by"))
  expect_setequal(a$tool_names(), names(tools))
})

test_that("host canvas tools are declared read-only by exact name", {
  skip_if_no_genui()
  o <- canvas_options(starter = FALSE, components = list(toy_output_component("violin")))
  a <- GenUIAdapter$new(data_env = genui_test_env(), options = o)
  a$prepare()
  meta <- .tool_metadata("canvas_violin")
  expect_true(meta$known)
  expect_identical(meta$capability, "read")
  expect_identical(check_permission("canvas_violin", mode = "plan",
                                    capability = meta$capability), "allow")
  expect_false(.tool_metadata("canvas_violin_extra")$known)
})

test_that("a host component goes through the same transactional executor", {
  skip_if_no_genui()
  o <- canvas_options(starter = FALSE, components = list(toy_output_component()))
  ops <- fake_genui_ops()
  a <- GenUIAdapter$new(data_env = genui_test_env(), options = o)
  a$bind(session = NULL, ops = ops$ops)
  a$begin_turn()
  res <- a$call("canvas_boxplot", list(dataset = "cars", y = "mpg", by = "cyl"))
  expect_true(genui_ok(res))
  expect_identical(ops$dom, "ca_genui_shell_c1")
  ops$fail_server <- function(module_id, args) TRUE
  bad <- a$call("canvas_boxplot", list(dataset = "cars", y = "hp", by = "cyl"))
  expect_false(genui_ok(bad))
  expect_identical(ops$dom, "ca_genui_shell_c1")
})

test_that("validate_text = FALSE lets a host component take URLs from the model", {
  skip_if_no_genui()
  link <- canvas_component_widget(
    "link_card", "Shows a link.",
    args = list(url = ellmer::type_string("A URL.")), data = FALSE,
    widget = function(args, data) htmltools::tags$a(href = args$url, args$url))
  url <- "https://example.org/report"
  strict <- GenUIAdapter$new(options = canvas_options(starter = FALSE,
                                                      components = list(link)))
  loose <- GenUIAdapter$new(options = canvas_options(starter = FALSE,
                                                     components = list(link),
                                                     validate_text = FALSE))
  for (a in list(strict, loose)) {
    a$bind(session = NULL, ops = fake_genui_ops()$ops)
    a$begin_turn()
  }
  expect_match(strict$call("canvas_link_card", list(url = url))@error, "Canvas text")
  expect_true(genui_ok(loose$call("canvas_link_card", list(url = url))))
})

test_that("csp = TRUE, FALSE or a string decides the Canvas tab's policy", {
  skip_if_no_genui()
  meta <- function(o) {
    html <- as.character(htmltools::renderTags(
      .genui_canvas_panel(o))$head)
    regmatches(html, regexpr('content="[^"]*"', html))
  }
  expect_match(meta(canvas_options()), "img-src &#39;self&#39;", fixed = TRUE)
  expect_length(meta(canvas_options(csp = FALSE)), 0L)
  expect_match(meta(canvas_options(csp = "img-src *")), "img-src \\*")
})

test_that("a saved canvas with a host component restores", {
  skip_if_no_genui()
  o <- canvas_options(starter = FALSE, components = list(toy_output_component()))
  ops <- fake_genui_ops()
  env <- genui_test_env()
  a <- GenUIAdapter$new(data_env = env, options = o)
  a$bind(session = NULL, ops = ops$ops); a$begin_turn()
  a$call("canvas_boxplot", list(dataset = "cars", y = "mpg", by = "cyl"))
  snap <- a$snapshot(character())
  ops2 <- fake_genui_ops()
  b <- GenUIAdapter$new(data_env = env, options = o)
  b$bind(session = NULL, ops = ops2$ops)
  expect_true(b$restore(snap)$ok)
  # A different host implementation under the same name fails closed.
  other <- canvas_component_output(
    "boxplot", "Box plot of a numeric column by group.",
    args = list(y = ellmer::type_string("Numeric column."),
                by = ellmer::type_string("Grouping column.")),
    output = shiny::plotOutput,
    render = function(args, data) shiny::renderPlot(graphics::plot(1)))
  c2 <- GenUIAdapter$new(data_env = env,
                         options = canvas_options(starter = FALSE, components = list(other)))
  c2$bind(session = NULL, ops = fake_genui_ops()$ops)
  expect_match(c2$restore(snap)$message, "components changed")
})

test_that("restore gives every component its own arguments and data", {
  # A component whose ui ignores its args leaves them as lazy promises until
  # the render function runs -- after the restore loop has moved on.
  skip_if_no_genui()
  echo <- canvas_component_output(
    "echo", "Echoes a column name and the row count.",
    args = list(col = ellmer::type_string("A column.")),
    output = shiny::textOutput,
    render = function(args, data) shiny::renderText(paste(args$col, nrow(data()))))
  o <- canvas_options(starter = FALSE, components = list(echo))
  env <- genui_test_env()
  rec <- GenUIAdapter$new(data_env = env, options = o)
  rec$bind(session = NULL, ops = fake_genui_ops()$ops); rec$begin_turn()
  rec$call("canvas_echo", list(dataset = "cars", col = "mpg"))
  rec$call("canvas_echo", list(dataset = "flowers", col = "Species"))
  snap <- rec$snapshot(character())

  session <- shiny::MockShinySession$new()
  a <- GenUIAdapter$new(data_env = env, options = o)
  a$bind(session = session, ops = .genui_shiny_ops(session))
  expect_true(shiny::isolate(a$restore(snap))$ok)
  expect_identical(shiny::isolate(session$getOutput("ca_genui_c1-out")), "mpg 32")
  expect_identical(shiny::isolate(session$getOutput("ca_genui_c2-out")), "Species 150")
})
