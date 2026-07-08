fake_board <- function(tasks) {
  data.frame(id = seq_along(tasks), prompt = tasks,
             owner = "w", status = "done", result = "ok",
             stringsAsFactors = FALSE)
}

test_that("team_lead runs one round when the lead declares done", {
  res <- team_lead(
    "build X",
    decompose_fn  = function(goal, model, cwd) list(tasks = c("t1", "t2"),
                                                    blocked_by = list(integer(0), 1L)),
    coordinate_fn = function(tasks, blocked_by) fake_board(tasks),
    review_fn     = function(goal, board, model, cwd) list(done = TRUE,
                                                           plan = list(tasks = character(0))))
  expect_s3_class(res, "data.frame")
  expect_equal(nrow(res), 2L)
  expect_true(all(res$round == 1L))
})

test_that("team_lead re-plans across rounds until the lead is done", {
  calls <- new.env(parent = emptyenv()); calls$n <- 0L
  res <- team_lead(
    "goal", max_rounds = 5L,
    decompose_fn  = function(goal, model, cwd) list(tasks = "t1", blocked_by = list(integer(0))),
    coordinate_fn = function(tasks, blocked_by) fake_board(tasks),
    review_fn     = function(goal, board, model, cwd) {
      calls$n <- calls$n + 1L
      if (calls$n < 2L) list(done = FALSE, plan = list(tasks = "t2", blocked_by = list(integer(0))))
      else list(done = TRUE, plan = list(tasks = character(0)))
    })
  expect_equal(sort(unique(res$round)), c(1L, 2L))
  expect_equal(nrow(res), 2L)
})

test_that("team_lead respects max_rounds when the lead never finishes", {
  res <- team_lead(
    "goal", max_rounds = 2L,
    decompose_fn  = function(goal, model, cwd) list(tasks = "t", blocked_by = list(integer(0))),
    coordinate_fn = function(tasks, blocked_by) fake_board(tasks),
    review_fn     = function(goal, board, model, cwd)
      list(done = FALSE, plan = list(tasks = "more", blocked_by = list(integer(0)))))
  expect_equal(max(res$round), 2L)
})

test_that("team_lead rejects an empty goal", {
  expect_error(team_lead(""), "goal")
  expect_error(team_lead(character(0)), "goal")
})

test_that(".parse_decomposition handles data.frame + list shapes and dep parsing", {
  df <- list(tasks = data.frame(description = c("a", "b"),
                                depends_on = c("", "1"), stringsAsFactors = FALSE))
  p1 <- codeagent:::.parse_decomposition(df)
  expect_equal(p1$tasks, c("a", "b"))
  expect_equal(p1$blocked_by[[1]], integer(0))
  expect_equal(p1$blocked_by[[2]], 1L)

  lst <- list(tasks = list(list(description = "x", depends_on = "1,2"),
                           list(description = "y")))
  p2 <- codeagent:::.parse_decomposition(lst)
  expect_equal(p2$tasks, c("x", "y"))
  expect_equal(p2$blocked_by[[1]], c(1L, 2L))
  expect_equal(p2$blocked_by[[2]], integer(0))

  expect_equal(codeagent:::.parse_decomposition(list())$tasks, character(0))
  # blank descriptions are dropped
  blank <- list(tasks = list(list(description = ""), list(description = "keep")))
  expect_equal(codeagent:::.parse_decomposition(blank)$tasks, "keep")
})

test_that(".lead_should_continue stops on max_rounds / done / empty plan", {
  expect_false(codeagent:::.lead_should_continue(2L, 2L, list(done = FALSE, plan = list(tasks = "x"))))
  expect_false(codeagent:::.lead_should_continue(1L, 3L, list(done = TRUE,  plan = list(tasks = "x"))))
  expect_false(codeagent:::.lead_should_continue(1L, 3L, list(done = FALSE, plan = list(tasks = character(0)))))
  expect_true (codeagent:::.lead_should_continue(1L, 3L, list(done = FALSE, plan = list(tasks = "x"))))
})
