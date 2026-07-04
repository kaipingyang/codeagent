# Tests for the Phase 3 Shiny async permission gate (.asyncify_gated_tool).
# The Shiny ask_fn/ask_question_fn themselves require a live session, so here we
# cover the reusable async-gate machinery: a promise-returning ask_fn is awaited,
# "allow" runs the inner tool, "deny" surfaces a clean tool rejection.

test_that(".asyncify_gated_tool awaits an async ask_fn and runs the tool on allow", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")

  inner <- write_tool(mode = "bypass")          # bypass -> inner never self-gates
  ask   <- function(tool_name, tool_input)
    promises::promise(function(resolve, reject)
      later::later(function() resolve(TRUE), 0))

  gated <- .asyncify_gated_tool(inner, "Write", mode = "default",
                                rules = list(), ask_fn = ask)
  expect_true(is.function(gated))
  expect_identical(gated@name, "Write")

  tmp <- tempfile(fileext = ".txt")
  pr  <- gated(file_path = tmp, content = "ALLOWED")
  expect_true(promises::is.promising(pr))

  out <- NULL; done <- FALSE
  promises::then(promises::as.promise(pr),
                 function(v) { out <<- v; done <<- TRUE },
                 function(e) { out <<- e; done <<- TRUE })
  for (i in 1:200) { later::run_now(0.01); if (done) break }

  expect_true(done)
  expect_true(file.exists(tmp))
  expect_identical(paste(readLines(tmp), collapse = ""), "ALLOWED")
  unlink(tmp)
})

test_that(".asyncify_gated_tool rejects cleanly when the ask_fn denies", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")

  inner <- write_tool(mode = "bypass")
  ask   <- function(tool_name, tool_input)
    promises::promise(function(resolve, reject)
      later::later(function() resolve(FALSE), 0))

  gated <- .asyncify_gated_tool(inner, "Write", mode = "default",
                                rules = list(), ask_fn = ask)

  tmp <- tempfile(fileext = ".txt")
  pr  <- gated(file_path = tmp, content = "DENIED")

  out <- NULL; done <- FALSE
  promises::then(promises::as.promise(pr),
                 function(v) { out <<- v; done <<- TRUE },
                 function(e) { out <<- e; done <<- TRUE })
  for (i in 1:200) { later::run_now(0.01); if (done) break }

  expect_true(done)
  # Denied: the inner tool must NOT have run, so the file is not created.
  expect_false(file.exists(tmp))
})

test_that(".asyncify_gated_tool denies immediately in plan mode without asking", {
  skip_if_not_installed("promises")
  skip_if_not_installed("later")

  asked <- FALSE
  ask   <- function(tool_name, tool_input) { asked <<- TRUE
    promises::promise_resolve(TRUE) }

  inner <- write_tool(mode = "bypass")
  gated <- .asyncify_gated_tool(inner, "Write", mode = "plan",
                                rules = list(), ask_fn = ask)

  tmp <- tempfile(fileext = ".txt")
  pr  <- gated(file_path = tmp, content = "NOPE")
  done <- FALSE
  promises::then(promises::as.promise(pr),
                 function(v) done <<- TRUE, function(e) done <<- TRUE)
  for (i in 1:200) { later::run_now(0.01); if (done) break }

  expect_false(asked)              # plan mode -> deny, ask_fn never consulted
  expect_false(file.exists(tmp))
})
