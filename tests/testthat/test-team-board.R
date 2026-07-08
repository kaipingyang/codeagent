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

# ---------------------------------------------------------------------------
# Task DAG: dependency-aware claim + pure helpers (12A phase 1)
# ---------------------------------------------------------------------------

test_that("board_claim skips a blocked task until its blocker is done", {
  db <- board_create(); on.exit(unlink(db), add = TRUE)
  a <- board_add_task(db, "A")
  b <- board_add_task(db, "B", blocked_by = a)   # B waits for A

  # First claim must be A (B is blocked); a second claim returns NULL (B still
  # blocked) even though B is pending.
  c1 <- board_claim(db, "w1")
  expect_equal(c1$prompt, "A")
  expect_null(board_claim(db, "w2"))             # B blocked -> nothing claimable

  # Complete A -> B becomes claimable.
  board_complete(db, a, "done-A")
  c2 <- board_claim(db, "w2")
  expect_false(is.null(c2))
  expect_equal(c2$prompt, "B")
})

test_that("board_claim with no deps is FIFO (backward compatible)", {
  db <- board_create(); on.exit(unlink(db), add = TRUE)
  board_add_task(db, "first"); board_add_task(db, "second")
  expect_equal(board_claim(db, "w1")$prompt, "first")
  expect_equal(board_claim(db, "w1")$prompt, "second")
})

test_that("board_claim handles a diamond DAG in dependency order", {
  db <- board_create(); on.exit(unlink(db), add = TRUE)
  a <- board_add_task(db, "A")
  b <- board_add_task(db, "B", blocked_by = a)
  cc <- board_add_task(db, "C", blocked_by = a)
  d <- board_add_task(db, "D", blocked_by = c(b, cc))

  expect_equal(board_claim(db, "w")$prompt, "A")   # only A unblocked
  expect_null(board_claim(db, "w"))                 # B,C,D blocked
  board_complete(db, a, "ra")
  got <- c(board_claim(db, "w")$prompt, board_claim(db, "w")$prompt)
  expect_setequal(got, c("B", "C"))                 # both unblocked, D still waits
  expect_null(board_claim(db, "w"))                 # D needs B and C done
})

test_that(".task_toposort orders by dependency and detects cycles", {
  deps <- data.frame(task_id = c(2L, 3L), blocker_id = c(1L, 2L))
  ord  <- codeagent:::.task_toposort(c(1L, 2L, 3L), deps)
  expect_equal(ord, c(1L, 2L, 3L))
  # index of a blocker must precede the task it blocks
  expect_lt(match(1L, ord), match(2L, ord))

  # a 2-cycle -> error
  cyc <- data.frame(task_id = c(1L, 2L), blocker_id = c(2L, 1L))
  expect_error(codeagent:::.task_toposort(c(1L, 2L), cyc), "cycle")
})

test_that(".claimable_ids mirrors the SQL claim eligibility", {
  tasks <- data.frame(
    id     = 1:3,
    owner  = c(NA_character_, NA_character_, NA_character_),
    status = c("done", "pending", "pending"),
    stringsAsFactors = FALSE
  )
  deps <- data.frame(task_id = c(3L), blocker_id = c(2L))  # 3 waits for 2
  # 2 is claimable (no blockers), 3 is not (blocker 2 not done), 1 is done.
  expect_equal(codeagent:::.claimable_ids(tasks, deps), 2L)

  # Mark 2 done -> 3 becomes claimable.
  tasks$status[2] <- "done"
  expect_equal(codeagent:::.claimable_ids(tasks, deps), 3L)
})
