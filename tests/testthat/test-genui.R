# codeagent-owned GenUI adapter (references/plan/41-genui-adapter.md, Phase 0).

.genui_starter <- function() {
  skip_if_not(.genui_available(), "shinygenui starter pack unavailable")
  shinygenui::genui_components_bslib(data = NULL)
}

test_that(".genui_admit_catalog keeps exactly the admitted components", {
  catalog <- .genui_admit_catalog(.genui_starter())
  expect_setequal(names(catalog),
                  c("value_box", "data_table", "scatter_plot", "histogram"))
})

test_that(".genui_admit_catalog never admits markdown_card", {
  # It keeps external img src and javascript: URLs (research report 2.4.4).
  catalog <- .genui_admit_catalog(.genui_starter())
  expect_false("markdown_card" %in% names(catalog))
})

test_that(".genui_admit_catalog ignores components outside the allowlist", {
  # The starter pack is a candidate pool upstream may grow. The allowlist is
  # what codeagent reviewed, so an unreviewed component is left out rather
  # than failing startup the day shinygenui ships a new one.
  skip_if_not(.genui_available(), "shinygenui starter pack unavailable")
  rogue <- shinygenui::genui_component(
    name = "rogue_widget", description = "not reviewed",
    ui = function(id, args) htmltools::div())
  catalog <- .genui_admit_catalog(c(.genui_starter(), list(rogue)))
  expect_false("rogue_widget" %in% names(catalog))
})

test_that(".genui_admit_catalog errors when an admitted component disappears", {
  # The opposite direction is a broken contract: the prompt would promise a
  # component the catalog cannot build.
  without_hist <- Filter(function(x) x$name != "histogram", .genui_starter())
  expect_error(.genui_admit_catalog(without_hist), "histogram")
})

.genui_toy <- function(name, args) {
  skip_if_not(.genui_available(), "shinygenui starter pack unavailable")
  shinygenui::genui_component(name = name, description = "toy", args = args,
                              ui = function(id, args) htmltools::div())
}

test_that(".genui_catalog_digest is deterministic", {
  catalog <- .genui_admit_catalog(.genui_starter())
  d <- .genui_catalog_digest(catalog)
  expect_type(d, "character")
  expect_length(d, 1L)
  expect_identical(.genui_catalog_digest(catalog), d)
})

test_that(".genui_catalog_digest does not depend on component order", {
  a <- .genui_toy("alpha", list(x = "An x."))
  b <- .genui_toy("beta",  list(y = "A y."))
  expect_identical(
    .genui_catalog_digest(shinygenui::genui_catalog(a, b)),
    .genui_catalog_digest(shinygenui::genui_catalog(b, a)))
})

test_that(".genui_catalog_digest changes when a component's arguments change", {
  # Same component name, different schema: a stale trace or permission
  # decision must not be reused against the new implementation.
  v1 <- shinygenui::genui_catalog(.genui_toy("alpha", list(x = "An x.")))
  v2 <- shinygenui::genui_catalog(.genui_toy("alpha", list(x = "An x.", z = "A z.")))
  expect_false(identical(.genui_catalog_digest(v1), .genui_catalog_digest(v2)))
})

test_that("component tools map to their shinygenui component name", {
  expect_identical(.genui_dispatch_name("canvas_scatter_plot"), "scatter_plot")
  expect_identical(.genui_tool_name("scatter_plot"), "canvas_scatter_plot")
})

test_that("lifecycle tools map to shinygenui's lifecycle call names", {
  expect_identical(.genui_dispatch_name("canvas_update"), "update_component")
  expect_identical(.genui_dispatch_name("canvas_remove"), "remove_component")
  expect_identical(.genui_dispatch_name("canvas_clear"),  "clear_canvas")
})

test_that("canvas_state is never dispatched", {
  # shinygenui rejects get_canvas_state; the adapter reads its own state.
  expect_null(.genui_dispatch_name("canvas_state"))
})

test_that("a name without the canvas_ prefix is not a GenUI tool", {
  expect_error(.genui_dispatch_name("scatter_plot"), "canvas_")
})

test_that(".genui_tool_names lists every component tool plus the lifecycle", {
  expect_setequal(.genui_tool_names(), c(
    "canvas_value_box", "canvas_data_table", "canvas_scatter_plot",
    "canvas_histogram", "canvas_update", "canvas_remove", "canvas_clear",
    "canvas_state"))
})

.genui_plan <- function(call_name, args, state = list(instances = list(), next_id = 1L)) {
  catalog <- .genui_admit_catalog(.genui_starter())
  shinygenui::genui_dispatch(catalog, shinygenui::genui_call(call_name, args),
                             state, data = mtcars)
}

test_that(".genui_plan_to_op strips the upstream class", {
  op <- .genui_plan_to_op(.genui_plan("scatter_plot", list(x = "mpg", y = "hp")))
  expect_false(inherits(op, "genui_plan"))
  expect_identical(op$action, "create")
  expect_identical(op$component, "scatter_plot")
  expect_identical(op$args$x, "mpg")
})

test_that("every op carries the same fields whatever its action", {
  state <- list(instances = list(c1 = list(component = "scatter_plot",
                                           args = list(x = "mpg", y = "hp"),
                                           parent_id = NULL)),
                next_id = 2L)
  create <- .genui_plan_to_op(.genui_plan("scatter_plot", list(x = "mpg", y = "hp")))
  clear  <- .genui_plan_to_op(.genui_plan("clear_canvas", list(), state))
  expect_identical(names(create), names(clear))
  expect_identical(clear$action, "clear")
  expect_identical(clear$ids, "c1")
})

test_that(".genui_plan_to_op refuses anything that is not a genui_plan", {
  expect_error(.genui_plan_to_op(list(action = "create")), "Expected a shinygenui plan")
})

.genui_create_op <- function() {
  .genui_plan_to_op(.genui_plan("scatter_plot", list(x = "mpg", y = "hp")))
}

test_that(".genui_artifact satisfies the v1 tool-artifact contract", {
  art <- .genui_artifact(.genui_create_op(), "digest123", "Added scatter_plot c1")
  expect_identical(tool_result_artifact(list(artifact = art))$kind, "generative_ui")
  expect_identical(art$schema, "codeagent.tool-artifact")
  expect_identical(art$version, 1L)
})

test_that(".genui_artifact payload carries exactly the safe fields", {
  # The payload is persisted with the session and shown by non-Shiny hosts, so
  # it must never grow to include the op's args (model-authored strings, data
  # references), rendered HTML, or observers.
  art <- .genui_artifact(.genui_create_op(), "digest123", "Added scatter_plot c1")
  expect_setequal(names(art$payload),
                  c("catalog_digest", "operation", "instance_ids", "safe_summary"))
  expect_identical(art$payload$operation, "create")
  expect_identical(art$payload$instance_ids, "c1")
})

test_that(".genui_artifact records every instance a clear removes", {
  state <- list(instances = list(
    c1 = list(component = "scatter_plot", args = list(), parent_id = NULL),
    c2 = list(component = "histogram",    args = list(), parent_id = NULL)),
    next_id = 3L)
  op  <- .genui_plan_to_op(.genui_plan("clear_canvas", list(), state))
  art <- .genui_artifact(op, "digest123", "Cleared canvas")
  expect_setequal(art$payload$instance_ids, c("c1", "c2"))
})

.genui_fragment <- function() {
  .genui_prompt_fragment(.genui_admit_catalog(.genui_starter()))
}

test_that("the prompt fragment does not redefine the agent's identity", {
  # The upstream template opens with "You are the interface engine ...",
  # which would override codeagent's own system prompt.
  expect_false(grepl("You are", .genui_fragment(), fixed = TRUE))
})

test_that("the prompt fragment does not shorten every chat reply", {
  # Upstream caps all replies at "one or two short sentences" -- right for a
  # dashboard app, wrong for a coding agent that only sometimes draws.
  expect_false(grepl("one or two short sentences", .genui_fragment(), fixed = TRUE))
})

test_that("the prompt fragment names tools by their registered names", {
  frag <- .genui_fragment()
  for (tool in .genui_tool_names())
    expect_match(frag, tool, fixed = TRUE, info = tool)
})

test_that("the prompt fragment never names an upstream lifecycle call", {
  # Those are dispatch names, not tools: a model told to call update_component
  # would call a tool that does not exist.
  frag <- .genui_fragment()
  for (upstream in c("update_component", "remove_component",
                     "clear_canvas", "get_canvas_state"))
    expect_false(grepl(upstream, frag, fixed = TRUE), info = upstream)
})

test_that("the prompt fragment omits components outside the catalog", {
  expect_false(grepl("markdown_card", .genui_fragment(), fixed = TRUE))
})

test_that("GenUIAdapter freezes the admitted catalog at construction", {
  skip_if_not(.genui_available(), "shinygenui starter pack unavailable")
  a <- GenUIAdapter$new()
  expect_setequal(names(a$catalog()),
                  c("value_box", "data_table", "scatter_plot", "histogram"))
  expect_identical(a$catalog(), a$catalog())
})

test_that("GenUIAdapter exposes the digest, tool names and prompt it was built from", {
  skip_if_not(.genui_available(), "shinygenui starter pack unavailable")
  a <- GenUIAdapter$new()
  expect_identical(a$digest(), .genui_catalog_digest(a$catalog()))
  expect_identical(a$tool_names(), .genui_tool_names())
  expect_identical(a$prompt_fragment(), .genui_prompt_fragment(a$catalog()))
})

test_that("GenUIAdapter explains a missing shinygenui instead of failing obscurely", {
  local_mocked_bindings(.genui_missing = function(...) "shinygenui")
  expect_error(GenUIAdapter$new(), "shinygenui")
})

test_that(".genui_missing names exactly the packages that are not installed", {
  expect_identical(.genui_missing(c("stats", "codeagent.no.such.pkg")),
                   "codeagent.no.such.pkg")
  expect_identical(.genui_missing("stats"), character())
})

test_that("GenUI counts the starter pack's own packages as prerequisites", {
  # genui_components_bslib() calls rlang::check_installed(c("ggplot2", "DT")):
  # shinygenui alone is not enough to build the catalog.
  local_mocked_bindings(.genui_missing = function(...) c("ggplot2", "DT"))
  expect_false(.genui_available())
  expect_error(GenUIAdapter$new(), "ggplot2.*DT")
})

test_that("genui is a capability group naming every canvas tool", {
  expect_setequal(.CODEAGENT_GROUPS$genui, .genui_tool_names())
  expect_setequal(.resolve_tool_spec("genui")$native, .genui_tool_names())
})

test_that("every canvas tool is a native read tool in the genui group", {
  for (tool in .genui_tool_names()) {
    meta <- .tool_metadata(tool)
    expect_true(meta$known, info = tool)
    expect_identical(meta$set, "A", info = tool)
    expect_identical(meta$capability, "read", info = tool)
    expect_identical(.tool_group(tool), "genui", info = tool)
  }
})

test_that("the canvas_ prefix alone never grants a capability", {
  # Canvas tools are registered by exact name. If the prefix were matched, any
  # host tool named canvas_* would inherit "read" and pass the plan boundary.
  meta <- .tool_metadata("canvas_rm_rf")
  expect_false(meta$known)
  expect_identical(.tool_capability("canvas_rm_rf"), "exec")
})
