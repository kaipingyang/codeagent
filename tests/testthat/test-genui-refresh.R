# Canvas data refresh and data fingerprints (references/plan/43-*.md).

last_rows <- function(ops) {
  servers <- Filter(function(x) identical(x$op, "server"), ops$log)
  servers[[length(servers)]]$rows
}

test_that("canvas_refresh is an adapter-owned lifecycle tool", {
  expect_null(.genui_dispatch_name("canvas_refresh"))
  expect_true("canvas_refresh" %in% .genui_tool_names())
  expect_identical(.tool_metadata("canvas_refresh")$capability, "read")
  expect_identical(.tool_group("canvas_refresh"), "genui")
})

test_that("refresh re-reads the data frame a component was built from", {
  skip_if_no_genui()
  h <- genui_test_adapter()
  h$adapter$call("canvas_histogram", list(dataset = "cars", column = "mpg"))
  expect_identical(last_rows(h$ops), 32L)
  h$env$cars <- utils::head(mtcars, 10)
  res <- h$adapter$call("canvas_refresh", list(id = "c1"))
  expect_true(genui_ok(res))
  expect_identical(last_rows(h$ops), 10L)
})

test_that("refresh without an id refreshes every data component and nothing else", {
  skip_if_no_genui()
  h <- genui_test_adapter()
  h$adapter$call("canvas_histogram", list(dataset = "cars", column = "mpg"))
  h$adapter$call("canvas_markdown_card", list(text = "note"))
  h$adapter$call("canvas_value_box", list(dataset = "cars", title = "t",
                                          column = "hp", agg = "max"))
  n_before <- length(Filter(function(x) identical(x$op, "server"), h$ops$log))
  h$env$cars <- utils::head(mtcars, 5)
  res <- h$adapter$call("canvas_refresh", list())
  expect_true(genui_ok(res))
  servers <- Filter(function(x) identical(x$op, "server"), h$ops$log)
  fresh <- servers[(n_before + 1L):length(servers)]
  expect_length(fresh, 2L)
  expect_true(all(vapply(fresh, function(x) identical(x$rows, 5L), logical(1L))))
})

test_that("refresh never changes the trace", {
  skip_if_no_genui()
  h <- genui_test_adapter()
  h$adapter$call("canvas_histogram", list(dataset = "cars", column = "mpg"))
  before <- h$adapter$snapshot()$trace
  h$adapter$call("canvas_refresh", list(id = "c1"))
  expect_identical(h$adapter$snapshot()$trace, before)
})

test_that("a refresh the new data no longer supports keeps the old view", {
  skip_if_no_genui()
  h <- genui_test_adapter()
  h$adapter$call("canvas_histogram", list(dataset = "cars", column = "mpg"))
  h$env$cars <- iris
  n_before <- length(h$ops$log)
  res <- h$adapter$call("canvas_refresh", list(id = "c1"))
  expect_false(genui_ok(res))
  expect_match(res@error, "mpg")
  expect_length(h$ops$log, n_before)
  expect_true("c1" %in% h$adapter$stale_ids())
})

test_that("refresh of an unknown id is an actionable error", {
  skip_if_no_genui()
  h <- genui_test_adapter()
  expect_match(h$adapter$call("canvas_refresh", list(id = "c9"))@error, "c9")
})

test_that("stale_ids names components whose data changed since they were drawn", {
  skip_if_no_genui()
  h <- genui_test_adapter()
  h$adapter$call("canvas_histogram", list(dataset = "cars", column = "mpg"))
  h$adapter$call("canvas_histogram", list(dataset = "flowers", column = "Sepal.Length"))
  expect_identical(h$adapter$stale_ids(), character())
  h$env$cars <- utils::head(mtcars, 3)
  expect_identical(h$adapter$stale_ids(), "c1")
  h$adapter$call("canvas_refresh", list(id = "c1"))
  expect_identical(h$adapter$stale_ids(), character())
})

test_that("a vanished data frame counts as stale", {
  skip_if_no_genui()
  h <- genui_test_adapter()
  h$adapter$call("canvas_histogram", list(dataset = "cars", column = "mpg"))
  rm("cars", envir = h$env)
  expect_identical(h$adapter$stale_ids(), "c1")
})

test_that("mark_stale tells the browser which components are out of date", {
  skip_if_no_genui()
  h <- genui_test_adapter()
  h$adapter$call("canvas_histogram", list(dataset = "cars", column = "mpg"))
  h$env$cars <- utils::head(mtcars, 3)
  h$adapter$mark_stale()
  expect_identical(h$ops$stale, "c1")
  h$adapter$call("canvas_refresh", list(id = "c1"))
  expect_identical(h$ops$stale, character())
})

test_that("restore reports components whose data changed since the save", {
  skip_if_no_genui()
  h <- genui_test_adapter()
  h$adapter$call("canvas_histogram", list(dataset = "cars", column = "mpg"))
  snap <- jsonlite::fromJSON(jsonlite::toJSON(h$adapter$snapshot(character()),
                                              auto_unbox = TRUE, null = "null"),
                             simplifyVector = FALSE)
  env2 <- genui_test_env(); env2$cars <- utils::head(mtcars, 8)
  h2 <- genui_test_adapter(env = env2)
  res <- h2$adapter$restore(snap)
  expect_true(res$ok)
  expect_identical(res$changed, "c1")
  expect_match(res$message, "c1")
  # The same data restores silently.
  h3 <- genui_test_adapter(env = h$env)
  res3 <- h3$adapter$restore(snap)
  expect_true(res3$ok)
  expect_length(res3$changed, 0L)
})

test_that("refresh counts towards the per-turn change quota", {
  skip_if_no_genui()
  h <- genui_test_adapter()
  h$adapter$call("canvas_histogram", list(dataset = "cars", column = "mpg"))
  for (i in seq_len(.GENUI_LIMITS$mutations_per_turn - 1L))
    h$adapter$call("canvas_refresh", list(id = "c1"))
  expect_match(h$adapter$call("canvas_refresh", list(id = "c1"))@error,
               "changes per turn")
})
