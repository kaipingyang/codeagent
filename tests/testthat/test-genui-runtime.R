# GenUI Phase 1-3 runtime: pure helpers, executor and adapter
# (references/plan/42-genui-phase1-3.md).

# -- dataset resolution -------------------------------------------------------

test_that(".genui_resolve_dataset returns the named data frame", {
  env <- genui_test_env()
  expect_identical(.genui_resolve_dataset("cars", env), mtcars)
})

test_that(".genui_resolve_dataset lists the data frames that do exist", {
  env <- genui_test_env()
  expect_error(.genui_resolve_dataset("nope", env),
               "No data frame named \"nope\".*cars, flowers")
})

test_that(".genui_resolve_dataset rejects an object that is not a data frame", {
  expect_error(.genui_resolve_dataset("not_a_frame", genui_test_env()),
               "\"not_a_frame\" is not a data frame")
})

test_that(".genui_resolve_dataset rejects a missing or malformed name", {
  env <- genui_test_env()
  expect_error(.genui_resolve_dataset(NULL, env), "`dataset` must name")
  expect_error(.genui_resolve_dataset(c("a", "b"), env), "`dataset` must name")
  expect_error(.genui_resolve_dataset("", env), "`dataset` must name")
})

# -- canvas-output validation -------------------------------------------------

test_that(".genui_validate_strings accepts ordinary titles and column names", {
  expect_null(.genui_validate_strings(list(title = "Miles per gallon (mpg)",
                                           columns = c("mpg", "cyl"))))
})

test_that(".genui_validate_strings rejects markup, links and control characters", {
  bad <- list(
    "<img src=x onerror=alert(1)>", "<script>", "javascript:alert(1)",
    "JavaScript:alert(1)", "data:text/html,hi", "see https://example.com",
    "www.example.com", "vbscript:x", "file:///etc/passwd",
    paste0("a", intToUtf8(7L), "b"))
  for (s in bad)
    expect_match(.genui_validate_strings(list(title = s)), "Canvas text", info = s)
})

test_that(".genui_validate_strings walks nested lists and vectors", {
  expect_match(.genui_validate_strings(list(a = list(b = c("ok", "<b>x</b>")))),
               "Canvas text")
})

# -- quota --------------------------------------------------------------------

test_that(".genui_quota_check passes a call within every limit", {
  expect_null(.genui_quota_check("create", list(title = "t"), live = 0L,
                                 turn_mutations = 0L, trace_len = 0L))
})

test_that(".genui_quota_check enforces the per-turn mutation limit", {
  lim <- .GENUI_LIMITS
  expect_match(.genui_quota_check("update", list(), live = 1L,
                                  turn_mutations = lim$mutations_per_turn,
                                  trace_len = 1L),
               "changes per turn")
})

test_that(".genui_quota_check caps live components only for creates", {
  lim <- .GENUI_LIMITS
  expect_match(.genui_quota_check("create", list(), live = lim$live_instances,
                                  turn_mutations = 0L, trace_len = 0L),
               "components")
  expect_null(.genui_quota_check("remove", list(), live = lim$live_instances,
                                 turn_mutations = 0L, trace_len = 0L))
})

test_that(".genui_quota_check bounds history, argument size, strings and arrays", {
  lim <- .GENUI_LIMITS
  expect_match(.genui_quota_check("create", list(), 0L, 0L, lim$trace_entries),
               "history")
  expect_match(.genui_quota_check(
    "create", list(title = strrep("a", lim$string_chars + 1L)), 0L, 0L, 0L),
    "characters")
  expect_match(.genui_quota_check(
    "create", list(columns = as.list(rep("a", lim$array_items + 1L))), 0L, 0L, 0L),
    "items")
  big <- stats::setNames(as.list(rep(strrep("a", 1000L), 20L)), paste0("k", 1:20))
  expect_match(.genui_quota_check("create", big, 0L, 0L, 0L), "bytes")
})

# -- output discovery ---------------------------------------------------------

test_that(".genui_output_ids finds every output each admitted component renders", {
  skip_if_no_genui()
  catalog <- .genui_admit_catalog(shinygenui::genui_components_bslib(data = NULL))
  args <- list(value_box = list(title = "t", column = "mpg", agg = "mean"),
               data_table = list(),
               scatter_plot = list(x = "mpg", y = "hp"),
               histogram = list(column = "mpg"))
  expected <- c(value_box = "m-value", data_table = "m-table",
                scatter_plot = "m-plot", histogram = "m-plot")
  for (nm in names(args)) {
    ui <- catalog[[nm]]$ui("m", args[[nm]])
    expect_identical(.genui_output_ids(ui), expected[[nm]], info = nm)
  }
})

test_that(".genui_output_ids ignores inputs", {
  ui <- htmltools::div(shiny::sliderInput("m-bins", "b", 1, 5, 3),
                       shiny::textOutput("m-v"))
  expect_identical(.genui_output_ids(ui), "m-v")
})

# -- trace fold ---------------------------------------------------------------

test_that(".genui_fold_trace replays a trace to the same final instances", {
  skip_if_no_genui()
  h <- genui_test_adapter()
  a <- h$adapter
  a$call("canvas_histogram", list(dataset = "cars", column = "mpg"))
  a$call("canvas_scatter_plot", list(dataset = "cars", x = "mpg", y = "hp"))
  a$call("canvas_update", list(id = "c2", args = '{"y": "wt"}'))
  a$call("canvas_remove", list(id = "c1"))
  folded <- .genui_fold_trace(a$catalog(), a$snapshot()$trace,
                              function(name) .genui_resolve_dataset(name, h$env))
  expect_identical(names(folded$instances), "c2")
  expect_identical(folded$instances$c2$args$y, "wt")
  expect_identical(folded$next_id, 3L)
})

test_that(".genui_fold_trace fails when a replayed call no longer validates", {
  skip_if_no_genui()
  h <- genui_test_adapter()
  h$adapter$call("canvas_histogram", list(dataset = "cars", column = "mpg"))
  trace <- h$adapter$snapshot()$trace
  env2 <- new.env(); env2$cars <- iris
  expect_error(.genui_fold_trace(h$adapter$catalog(), trace,
                                 function(name) .genui_resolve_dataset(name, env2)),
               "mpg")
})

# -- summary ------------------------------------------------------------------

test_that(".genui_state_summary is empty for an empty canvas and bounded otherwise", {
  expect_identical(.genui_state_summary(list(instances = list())), "")
  inst <- stats::setNames(lapply(1:20, function(i)
    list(component = "histogram", dataset = "cars", args = list())),
    paste0("c", 1:20))
  s <- .genui_state_summary(list(instances = inst), max = 5L)
  expect_match(s, "c1 histogram \\(dataset cars\\)")
  expect_match(s, "15 more")
  expect_false(grepl("c6 ", s, fixed = TRUE))
})

# -- adapter: lazy preparation --------------------------------------------------

test_that("GenUIAdapter can be created without building the catalog", {
  calls <- 0L
  local_mocked_bindings(.genui_build_catalog = function() {
    calls <<- calls + 1L
    stop("should stay lazy")
  })
  a <- GenUIAdapter$new(prepare = FALSE)
  expect_false(a$prepared())
  expect_identical(calls, 0L)
})

test_that("GenUIAdapter builds the catalog once, on first use", {
  skip_if_no_genui()
  a <- GenUIAdapter$new(prepare = FALSE)
  first <- a$catalog()
  expect_true(a$prepared())
  expect_identical(a$catalog(), first)
})

# -- adapter: tool definitions ------------------------------------------------

test_that("GenUIAdapter builds one ToolDef per canvas tool name", {
  skip_if_no_genui()
  a <- GenUIAdapter$new()
  tools <- a$tools()
  expect_setequal(vapply(tools, function(t) t@name, ""), .genui_tool_names())
})

test_that("component tools take the component's arguments plus dataset", {
  skip_if_no_genui()
  a <- GenUIAdapter$new()
  tools <- a$tools()
  names(tools) <- vapply(tools, function(t) t@name, "")
  props <- names(tools$canvas_scatter_plot@arguments@properties)
  expect_setequal(props, c(names(a$catalog()$scatter_plot$args), "dataset"))
})

# -- adapter: calls -----------------------------------------------------------

test_that("an unbound adapter refuses every mutation", {
  skip_if_no_genui()
  a <- GenUIAdapter$new(data_env = genui_test_env())
  res <- a$call("canvas_histogram", list(dataset = "cars", column = "mpg"))
  expect_false(genui_ok(res))
  expect_match(res@error, "not attached")
})

test_that("a create mounts a shell, starts its server and returns the new id", {
  skip_if_no_genui()
  h <- genui_test_adapter()
  res <- h$adapter$call("canvas_histogram", list(dataset = "cars", column = "mpg"))
  expect_true(genui_ok(res))
  expect_match(res@value, "\"c1\"")
  expect_identical(h$ops$dom, "ca_genui_shell_c1")
  art <- res@extra$codeagent$artifact
  expect_identical(art$kind, "generative_ui")
  expect_identical(art$payload$operation, "create")
  expect_identical(art$payload$instance_ids, "c1")
})

test_that("a rejected create changes nothing and explains why", {
  skip_if_no_genui()
  h <- genui_test_adapter()
  res <- h$adapter$call("canvas_histogram", list(dataset = "cars", column = "nope"))
  expect_false(genui_ok(res))
  expect_match(res@error, "nope")
  expect_identical(h$ops$dom, character())
  expect_length(h$adapter$snapshot()$trace, 0L)
})

test_that("a create whose server fails is rolled back completely", {
  skip_if_no_genui()
  h <- genui_test_adapter()
  h$ops$fail_server <- function(module_id, args) TRUE
  res <- h$adapter$call("canvas_histogram", list(dataset = "cars", column = "mpg"))
  expect_false(genui_ok(res))
  expect_identical(h$ops$dom, character())
  # The failed attempt's whole module scope is destroyed, including observers
  # its server created but never returned.
  expect_true("ca_genui_c1" %in% h$ops$scopes)
  expect_length(h$adapter$snapshot()$trace, 0L)
  # The id was never committed, so the next create reuses it.
  h$ops$fail_server <- NULL
  ok <- h$adapter$call("canvas_histogram", list(dataset = "cars", column = "mpg"))
  expect_match(ok@value, "\"c1\"")
})

test_that("an update whose server fails restores the previous arguments", {
  skip_if_no_genui()
  h <- genui_test_adapter()
  h$adapter$call("canvas_histogram", list(dataset = "cars", column = "mpg"))
  h$ops$fail_server <- function(module_id, args) identical(args$column, "hp")
  res <- h$adapter$call("canvas_update", list(id = "c1", args = '{"column": "hp"}'))
  expect_false(genui_ok(res))
  expect_identical(h$adapter$state()$instances$c1$args$column, "mpg")
  expect_length(h$adapter$snapshot()$trace, 1L)
  servers <- Filter(function(x) identical(x$op, "server"), h$ops$log)
  expect_length(servers, 3L)   # original, failed new, restored original
})

test_that("remove and clear tear down shells, outputs and observers", {
  skip_if_no_genui()
  h <- genui_test_adapter()
  h$adapter$call("canvas_histogram", list(dataset = "cars", column = "mpg"))
  h$adapter$call("canvas_scatter_plot", list(dataset = "cars", x = "mpg", y = "hp"))
  h$adapter$call("canvas_remove", list(id = "c1"))
  expect_identical(h$ops$dom, "ca_genui_shell_c2")
  expect_identical(h$ops$scopes, "ca_genui_c1")
  expect_identical(h$ops$destroyed, 1L)
  h$adapter$call("canvas_clear", list())
  expect_identical(h$ops$dom, character())
  expect_setequal(h$ops$scopes, c("ca_genui_c1", "ca_genui_c2"))
  expect_identical(h$ops$destroyed, 2L)
  expect_length(h$adapter$state()$instances, 0L)
})

test_that("canvas_state reports instances and embedded input values", {
  skip_if_no_genui()
  h <- genui_test_adapter()
  h$adapter$call("canvas_histogram", list(dataset = "cars", column = "mpg"))
  h$ops$inputs[["ca_genui_c1"]] <- list(bins = 12L)
  res <- h$adapter$call("canvas_state", list())
  expect_true(genui_ok(res))
  expect_match(res@value, "\"c1\"")
  expect_match(res@value, "\"bins\":12")
  expect_match(res@value, "\"dataset\":\"cars\"")
})

test_that("display strings are validated before anything reaches the DOM", {
  skip_if_no_genui()
  h <- genui_test_adapter()
  res <- h$adapter$call("canvas_histogram",
                        list(dataset = "cars", column = "mpg",
                             title = "<img src=https://x.invalid/a.png>"))
  expect_false(genui_ok(res))
  expect_match(res@error, "Canvas text")
  expect_length(h$ops$log, 0L)
})

test_that("the per-turn quota resets when the next turn begins", {
  skip_if_no_genui()
  h <- genui_test_adapter()
  for (i in seq_len(.GENUI_LIMITS$mutations_per_turn))
    expect_true(genui_ok(h$adapter$call(
      "canvas_histogram", list(dataset = "cars", column = "mpg"))))
  res <- h$adapter$call("canvas_histogram", list(dataset = "cars", column = "mpg"))
  expect_match(res@error, "changes per turn")
  h$adapter$begin_turn()
  expect_true(genui_ok(h$adapter$call("canvas_clear", list())))
})

test_that("a cancelled turn accepts no further mutation", {
  skip_if_no_genui()
  h <- genui_test_adapter()
  h$adapter$cancel_turn()
  res <- h$adapter$call("canvas_histogram", list(dataset = "cars", column = "mpg"))
  expect_match(res@error, "cancelled")
  expect_length(h$ops$log, 0L)
})

test_that("a second browser session poisons a shared adapter", {
  skip_if_no_genui()
  h <- genui_test_adapter()
  h$adapter$bind(session = "another", ops = h$ops$ops)
  res <- h$adapter$call("canvas_histogram", list(dataset = "cars", column = "mpg"))
  expect_match(res@error, "more than one browser session")
})

test_that("each committed op records the request that made it", {
  skip_if_no_genui()
  h <- genui_test_adapter()
  req <- ellmer::ContentToolRequest(id = "req-1", name = "canvas_histogram",
                                    arguments = list())
  ellmer::with_tool_context(list(request = req, turns = list()), {
    h$adapter$call("canvas_histogram", list(dataset = "cars", column = "mpg"))
  })
  expect_identical(h$adapter$snapshot()$trace[[1]]$request_id, "req-1")
})

test_that("every canvas ToolDef runs end to end, including argument-less ones", {
  skip_if_no_genui()
  h <- genui_test_adapter()
  tools <- h$adapter$tools()
  names(tools) <- vapply(tools, function(t) t@name, "")
  expect_true(genui_ok(tools$canvas_histogram(dataset = "cars", column = "mpg")))
  expect_true(genui_ok(tools$canvas_update(id = "c1", args = '{"bins": 10}')))
  expect_true(genui_ok(tools$canvas_state()))
  expect_true(genui_ok(tools$canvas_remove(id = "c1")))
  expect_true(genui_ok(tools$canvas_clear()))
  # Wrappers (Data Shield, input hooks) call the underlying closure with
  # do.call(); argument-less tools must survive that too.
  for (nm in c("canvas_state", "canvas_clear"))
    expect_true(genui_ok(do.call(S7::S7_data(tools[[nm]]), list())), info = nm)
})

test_that("without session$destroy() the executor falls back to nulling outputs", {
  skip_if_no_genui()
  h <- genui_test_adapter()
  h$ops$can_destroy <- FALSE
  h$adapter$call("canvas_histogram", list(dataset = "cars", column = "mpg"))
  h$adapter$call("canvas_remove", list(id = "c1"))
  expect_true("ca_genui_c1-plot" %in% h$ops$nulled)
})

test_that("an update mounts a fresh module scope and destroys the old one", {
  skip_if_no_genui()
  h <- genui_test_adapter()
  h$adapter$call("canvas_histogram", list(dataset = "cars", column = "mpg"))
  h$adapter$call("canvas_update", list(id = "c1", args = '{"column": "hp"}'))
  servers <- vapply(Filter(function(x) identical(x$op, "server"), h$ops$log),
                    function(x) x$module_id, "")
  expect_identical(servers, c("ca_genui_c1", "ca_genui_c1_2"))
  expect_identical(h$ops$scopes, "ca_genui_c1")
  # canvas_state reads the live scope's inputs.
  h$ops$inputs[["ca_genui_c1_2"]] <- list(bins = 7L)
  expect_match(h$adapter$call("canvas_state", list())@value, "\"bins\":7")
})

test_that("Shiny's module destroy stops a mounted component's render observer", {
  skip_if_no_genui()
  session <- shiny::MockShinySession$new()
  skip_if_not(is.function(session$destroy), "Shiny without session$destroy()")
  ops <- .genui_shiny_ops(session)
  catalog <- .genui_build_catalog()
  observer <- function() session$.__enclos_env__$private$outs[["ca_genui_c1-plot"]]$obs
  rt <- shiny::isolate(.genui_mount(catalog$histogram, "c1", list(column = "mpg"),
                                    function() mtcars, ops))
  expect_false(isTRUE(observer()$.destroyed))
  .genui_unmount("c1", rt, ops)
  expect_true(observer()$.destroyed)
})
