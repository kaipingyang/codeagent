# tests/testthat/test-workspace-layout.R
# Pure workspace layout engine.

tab_ids <- function(l) vapply(l$tabs, `[[`, "", "id")
titles <- function(l) vapply(l$tabs, `[[`, "", "title")

test_that("opening content already open only focuses it", {
  l <- .ws_layout()
  l <- .ws_open(l, "result", "r1", "Read a.R")
  l <- .ws_open(l, "result", "r2", "Read b.R")
  expect_identical(l$active, "t_2")
  l <- .ws_open(l, "result", "r1", "Read a.R again")
  expect_identical(tab_ids(l), c("t_1", "t_2"))
  expect_identical(l$active, "t_1")
  expect_identical(titles(l)[[1]], "Read a.R")
  # same content id, other kind: another tab
  l <- .ws_open(l, "file", "r1")
  expect_length(l$tabs, 3L)
})

test_that("reveal = FALSE opens in the background", {
  l <- .ws_open(.ws_layout(), "result", "r1")
  l <- .ws_open(l, "result", "r2", reveal = FALSE)
  expect_identical(l$active, "t_1")
  expect_length(l$tabs, 2L)
  # the first tab of an empty layout is shown even without reveal
  expect_identical(.ws_open(.ws_layout(), "result", "x", reveal = FALSE)$active, "t_1")
})

test_that("closing the active tab focuses its right neighbour, else the left", {
  l <- .ws_layout()
  for (r in c("a", "b", "c")) l <- .ws_open(l, "result", r)
  l <- .ws_focus(l, "t_2")
  l <- .ws_close(l, "t_2")
  expect_identical(l$active, "t_3")
  l <- .ws_close(l, "t_3")
  expect_identical(l$active, "t_1")
  l <- .ws_close(l, "t_1")
  expect_null(l$active)
  expect_length(l$tabs, 0L)
})

test_that("closing a background tab keeps the active one", {
  l <- .ws_layout()
  for (r in c("a", "b")) l <- .ws_open(l, "result", r)
  expect_identical(.ws_close(l, "t_1")$active, "t_2")
})

test_that("pinned tabs sort first, cannot be closed, and catch the last close", {
  l <- .ws_open(.ws_layout(), "result", "a")
  l <- .ws_open(l, "files", "files", "Files", pinned = TRUE)
  l <- .ws_open(l, "canvas", "canvas", "Canvas", pinned = TRUE)
  expect_identical(vapply(l$tabs, `[[`, "", "kind"), c("files", "canvas", "result"))
  expect_identical(.ws_close(l, "t_2")$tabs, l$tabs)        # pinned: no-op
  l <- .ws_focus(l, "t_1")
  l <- .ws_close(l, "t_1")                                  # last unpinned
  expect_identical(l$active, "t_2")                         # first pinned
})

test_that("pin and unpin reorder; a user-pinned tab survives close others", {
  l <- .ws_layout()
  for (r in c("a", "b", "c")) l <- .ws_open(l, "result", r)
  l <- .ws_pin(l, "t_3")
  expect_identical(tab_ids(l), c("t_3", "t_1", "t_2"))
  l <- .ws_close_others(l, "t_1")
  expect_identical(tab_ids(l), c("t_3", "t_1"))
  expect_identical(l$active, "t_1")
  l <- .ws_pin(l, "t_3", FALSE)
  expect_identical(tab_ids(l), c("t_3", "t_1"))
  expect_identical(tab_ids(.ws_close(l, "t_3")), "t_1")
})

test_that("past max_tabs the least recently viewed unpinned tab goes", {
  l <- .ws_open(.ws_layout(), "files", "files", pinned = TRUE)
  for (r in c("a", "b", "c")) l <- .ws_open(l, "result", r, max_tabs = 4)
  l <- .ws_focus(l, "t_2")                                  # a viewed again
  l <- .ws_open(l, "result", "d", max_tabs = 4)
  expect_identical(vapply(l$tabs, `[[`, "", "content_id"), c("files", "a", "c", "d"))
  expect_identical(l$active, "t_5")
  # only pinned tabs left to evict: stop, keep the new one
  p <- .ws_layout()
  for (r in c("x", "y")) p <- .ws_open(p, "k", r, pinned = TRUE)
  p <- .ws_open(p, "result", "z", max_tabs = 2)
  expect_length(p$tabs, 3L)
})

test_that("unknown ids are no-ops", {
  l <- .ws_open(.ws_layout(), "result", "a")
  for (f in list(.ws_close, .ws_focus, .ws_close_others, .ws_pin))
    expect_identical(f(l, "t_99"), l)
  expect_identical(.ws_close(l, NA_character_), l)
  expect_identical(.ws_focus(l, c("t_1", "t_1")), l)
})

test_that("a stored layout is validated on the way back", {
  l <- .ws_layout()
  for (r in c("a", "b")) l <- .ws_open(l, "result", r)
  l <- .ws_focus(l, "t_1")
  back <- .ws_validate(jsonlite::fromJSON(jsonlite::toJSON(l, auto_unbox = TRUE, null = "null"),
                                          simplifyVector = FALSE))
  expect_identical(tab_ids(back), tab_ids(l))
  expect_identical(back$active, "t_1")
  expect_identical(back$next_id, 3L)
  bad <- list(tabs = list(list(id = "t_1", kind = "result", content_id = "a"),
                          list(id = "t_1", kind = "result", content_id = "dup"),
                          list(id = "t_7", kind = 3, content_id = "x"),
                          "junk"),
              active = "t_9", next_id = "x")
  v <- .ws_validate(bad)
  expect_identical(tab_ids(v), "t_1")
  expect_identical(v$active, "t_1")
  expect_identical(v$next_id, 2L)
  expect_identical(.ws_validate(NULL), .ws_layout())
})
