test_that(".board_progress summarises counts and percent", {
  empty <- codeagent:::.board_progress(NULL)
  expect_equal(empty$total, 0L)
  expect_equal(empty$pct, 0)

  df <- data.frame(
    status = c("done", "done", "claimed", "pending"),
    stringsAsFactors = FALSE
  )
  p <- codeagent:::.board_progress(df)
  expect_equal(p$total, 4L)
  expect_equal(p$done, 2L)
  expect_equal(p$claimed, 1L)
  expect_equal(p$pending, 1L)
  expect_equal(p$pct, 50)
})

test_that(".board_status_class maps statuses to bootstrap classes", {
  expect_equal(codeagent:::.board_status_class("done"), "success")
  expect_equal(codeagent:::.board_status_class("claimed"), "warning")
  expect_equal(codeagent:::.board_status_class("pending"), "secondary")
  expect_equal(codeagent:::.board_status_class(NULL), "secondary")
})

test_that("team_dashboard builds a shiny app object", {
  db <- board_create(); on.exit(unlink(db), add = TRUE)
  app <- team_dashboard(db)
  expect_s3_class(app, "shiny.appobj")
})
