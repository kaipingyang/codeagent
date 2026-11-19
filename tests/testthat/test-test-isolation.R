# tests/testthat/test-test-isolation.R
# The suite never writes into the developer's own codeagent directory.

test_that("tests run with a throwaway CODEAGENT_HOME", {
  home <- Sys.getenv("CODEAGENT_HOME")
  expect_true(nzchar(home))
  expect_true(startsWith(normalizePath(home, mustWork = FALSE),
                         normalizePath(tempdir(), mustWork = FALSE)))
  expect_identical(.get_codeagent_dir(), home)
})

test_that("a session saved without an explicit home lands in the throwaway one", {
  cwd <- withr::local_tempdir()
  ch <- ellmer::chat_anthropic(model = "claude-sonnet-4-6")
  ch$set_turns(list(ellmer::Turn("user", "q")))
  sid <- save_session(ch, cwd = cwd)
  path <- .find_session_path(sid, cwd)
  expect_true(startsWith(normalizePath(path), normalizePath(Sys.getenv("CODEAGENT_HOME"))))
})
