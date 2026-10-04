# Contract with the installed shinygenui.
#
# codeagent consumes only shinygenui's exported pure functions and owns the
# executor itself (references/plan/41-genui-adapter.md). These tests pin the
# upstream behaviour that design depends on, so an upstream release that
# changes it fails here on purpose -- the same idea as the .BTW_GROUPS drift
# guard -- instead of surfacing later as a broken canvas.

.genui_contract_catalog <- function() {
  skip_if_not(.genui_available(), "shinygenui starter pack unavailable")
  starter <- shinygenui::genui_components_bslib(data = NULL)
  keep <- Filter(function(x) x$name %in%
                   c("value_box", "data_table", "scatter_plot", "histogram"),
                 starter)
  do.call(shinygenui::genui_catalog, keep)
}

.genui_contract_state <- function() list(instances = list(), next_id = 1L)

test_that("the starter pack still ships the components the plan admits", {
  skip_if_not(.genui_available(), "shinygenui starter pack unavailable")
  names_ <- vapply(shinygenui::genui_components_bslib(data = NULL),
                   function(x) x$name, character(1L))
  expect_true(all(c("value_box", "data_table", "scatter_plot", "histogram")
                  %in% names_))
  # Excluded by host policy; its presence is what makes the filter necessary.
  expect_true("markdown_card" %in% names_)
})

test_that("an unbound catalog keeps column arguments as plain strings", {
  catalog <- .genui_contract_catalog()
  # Decision 6: column names must not be compiled into the tool schema.
  expect_s3_class(catalog[["scatter_plot"]]$args$x, "ellmer::TypeBasic")
})

test_that("genui_dispatch is a pure create/update/remove/clear planner", {
  catalog <- .genui_contract_catalog()
  st <- .genui_contract_state()
  create <- shinygenui::genui_dispatch(
    catalog, shinygenui::genui_call("scatter_plot", list(x = "mpg", y = "hp")),
    st, data = mtcars)
  expect_s3_class(create, "genui_plan")
  expect_identical(create$action, "create")
  expect_setequal(names(create), c("action", "id", "component", "args", "parent_id"))

  st$instances[[create$id]] <- list(component = create$component,
                                    args = create$args, parent_id = NULL)
  st$next_id <- 2L
  update <- shinygenui::genui_dispatch(
    catalog, shinygenui::genui_call("update_component",
                                    list(id = create$id, args = '{"x":"wt"}')),
    st, data = mtcars)
  expect_identical(update$action, "update")

  remove <- shinygenui::genui_dispatch(
    catalog, shinygenui::genui_call("remove_component", list(id = create$id)), st)
  expect_identical(remove$action, "remove")
  expect_true("ids" %in% names(remove))

  clear <- shinygenui::genui_dispatch(
    catalog, shinygenui::genui_call("clear_canvas", list()), st)
  expect_identical(clear$action, "clear")
  expect_true("ids" %in% names(clear))
})

test_that("get_canvas_state is not a dispatchable call", {
  # Why canvas_state must read adapter state directly instead of dispatching.
  catalog <- .genui_contract_catalog()
  expect_error(
    shinygenui::genui_dispatch(
      catalog, shinygenui::genui_call("get_canvas_state", list()),
      .genui_contract_state()),
    "get_canvas_state")
})

test_that("dispatch rejects the four classes of bad model calls", {
  catalog <- .genui_contract_catalog()
  st <- .genui_contract_state()
  call <- function(tool, args) shinygenui::genui_call(tool, args)
  expect_error(shinygenui::genui_dispatch(catalog, call("evil_component", list()), st),
               "evil_component")
  expect_error(shinygenui::genui_dispatch(
    catalog, call("scatter_plot", list(x = "mpg", y = "hp", onclick = "alert(1)")),
    st, data = mtcars), "onclick")
  expect_error(shinygenui::genui_dispatch(
    catalog, call("scatter_plot", list(x = "mpg")), st, data = mtcars), "y")
  # The unbound catalog still rejects a hallucinated column at dispatch time.
  expect_error(shinygenui::genui_dispatch(
    catalog, call("scatter_plot", list(x = "nope", y = "hp")), st, data = mtcars),
    "nope")
})

test_that("genui_prompt accepts a host-owned template string", {
  catalog <- .genui_contract_catalog()
  out <- shinygenui::genui_prompt(
    catalog, template = "HOST{{#components}}|{{name}}{{/components}}")
  expect_match(out, "^HOST")
  expect_match(out, "scatter_plot", fixed = TRUE)
})
