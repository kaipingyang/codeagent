# tests/testthat/test-team-board.R
# Tests for the SQLite shared task board + coordinator (multi-agent mesh).

skip_if_not_installed("DBI")
skip_if_not_installed("RSQLite")

test_that("board_create makes a usable board", {
  db <- board_create()
  on.exit(unlink(db), add = TRUE)
  st <- board_status(db)
  expect_s3_class(st, "data.frame")
  expect_equal(nrow(st), 0L)
})

test_that("board_add_task + board_status round-trips", {
  db <- board_create(); on.exit(unlink(db), add = TRUE)
  id1 <- board_add_task(db, "do X")
  id2 <- board_add_task(db, "do Y")
  expect_true(id2 > id1)
  st <- board_status(db)
  expect_equal(nrow(st), 2L)
  expect_setequal(st$prompt, c("do X", "do Y"))
  expect_true(all(st$status == "pending"))
})

test_that("board_claim is atomic -- no two workers get the same task", {
  db <- board_create(); on.exit(unlink(db), add = TRUE)
  board_add_task(db, "A"); board_add_task(db, "B")
  c1 <- board_claim(db, "w1")
  c2 <- board_claim(db, "w2")
  c3 <- board_claim(db, "w3")
  expect_false(is.null(c1))
  expect_false(is.null(c2))
  expect_null(c3)                       # board drained
  expect_false(identical(c1$id, c2$id)) # distinct tasks
  expect_setequal(c(c1$prompt, c2$prompt), c("A", "B"))
})

test_that("board_complete records result and drains pending", {
  db <- board_create(); on.exit(unlink(db), add = TRUE)
  board_add_task(db, "task")
  cl <- board_claim(db, "w1")
  expect_equal(codeagent:::.board_pending_count(db), 1L)
  board_complete(db, cl$id, "the result")
  expect_equal(codeagent:::.board_pending_count(db), 0L)
  st <- board_status(db)
  expect_equal(st$status, "done")
  expect_equal(st$result, "the result")
})

test_that("board messages broadcast and directed delivery", {
  db <- board_create(); on.exit(unlink(db), add = TRUE)
  board_send_message(db, "w1", "broadcast hi")               # broadcast
  board_send_message(db, "w2", "for coord", "coordinator")    # directed
  # Coordinator sees broadcast + its own
  coord <- board_messages(db, "coordinator")
  expect_equal(nrow(coord), 2L)
  # A different recipient sees only the broadcast
  other <- board_messages(db, "w9")
  expect_equal(nrow(other), 1L)
  # All messages
  expect_equal(nrow(board_messages(db)), 2L)
})

test_that("team_coordinate returns the board for empty tasks", {
  res <- team_coordinate(character(0))
  expect_s3_class(res, "data.frame")
  expect_equal(nrow(res), 0L)
})

test_that("team_coordinate validates tasks type", {
  expect_error(team_coordinate(list(1, 2)), "character")
})

test_that("team_coordinate_tool builds a valid ellmer tool", {
  skip_if_not_installed("mirai")
  t <- codeagent:::team_coordinate_tool(model = "claude-sonnet-4-6")
  expect_true(inherits(t, "ellmer::ToolDef"))
})
