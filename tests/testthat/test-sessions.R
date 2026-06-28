test_that("save_session and get_session_messages round-trip correctly", {
  skip_if_not_installed("ellmer")
  tmp_dir <- withr::local_tempdir()

  # Build a minimal fake chat with a known conversation
  chat <- ellmer::chat_anthropic(
    model         = "claude-haiku-4-5-20251001",
    system_prompt = "test"
  )
  # Add a user turn manually so we don't need an API call
  user_turn <- tryCatch(
    ellmer::Turn("user", list(ellmer::ContentText("Hello!"))),
    error = function(e) NULL
  )
  if (is.null(user_turn)) skip("ellmer Turn API not available")

  tryCatch(chat$set_turns(list(user_turn)), error = function(e) skip("set_turns failed"))

  sid <- save_session(chat, cwd = tmp_dir)
  expect_true(nzchar(sid))

  # File is stored under the codeagent project session directory
  session_dir  <- codeagent:::.get_project_session_dir(tmp_dir)
  session_file <- file.path(session_dir, paste0(sid, ".jsonl"))
  expect_true(file.exists(session_file))

  msgs <- get_session_messages(sid, directory = tmp_dir)
  expect_true(length(msgs) >= 1L)
  expect_equal(msgs[[1L]]$type, "user")
  expect_equal(msgs[[1L]]$text, "Hello!")
})

test_that("list_sessions returns sessions sorted by last_modified descending", {
  tmp_dir     <- withr::local_tempdir()
  session_dir <- codeagent:::.ensure_session_dir(tmp_dir)

  # Create two fake JSONL files with different timestamps
  sid1 <- codeagent:::.generate_uuid_v4()
  sid2 <- codeagent:::.generate_uuid_v4()
  f1   <- file.path(session_dir, paste0(sid1, ".jsonl"))
  f2   <- file.path(session_dir, paste0(sid2, ".jsonl"))

  hdr <- function(sid) {
    jsonlite::toJSON(list(type = "session-start", sessionId = sid,
                          cwd = tmp_dir, timestamp = "2026-01-01T00:00:00Z",
                          model = "test"), auto_unbox = TRUE)
  }
  writeLines(hdr(sid1), f1)
  Sys.sleep(0.1)  # ensure different mtime
  writeLines(hdr(sid2), f2)

  sessions <- list_sessions(directory = tmp_dir)
  expect_gte(length(sessions), 2L)
  # Most recent first
  times <- vapply(sessions, function(s) s$last_modified, numeric(1))
  expect_true(all(diff(times) <= 0))
})

test_that(".read_session_info returns NULL for non-existent file", {
  result <- codeagent:::.read_session_info("fake-id", "/nonexistent/path.jsonl")
  expect_null(result)
})

test_that(".read_sessions_from_dir handles empty and non-existent dirs", {
  expect_equal(codeagent:::.read_sessions_from_dir("/nonexistent/dir"), list())
  tmp <- withr::local_tempdir()
  expect_equal(codeagent:::.read_sessions_from_dir(tmp), list())
})

test_that("get_session_messages returns empty list for missing session", {
  result <- get_session_messages("00000000-0000-4000-8000-000000000000",
                                  directory = withr::local_tempdir())
  expect_equal(result, list())
})

test_that("save_session produces valid ISO 8601 timestamps (decimal point preserved)", {
  # Regression: sub('\\\\.',...) was removing the decimal point, producing
  # '2026-04-16T12:34:56789Z' instead of '2026-04-16T12:34:56.789Z'.
  skip_if_not_installed("ellmer")
  tmp_dir <- withr::local_tempdir()

  chat <- ellmer::chat_anthropic(
    model = "claude-haiku-4-5-20251001", system_prompt = "t")
  user_turn <- tryCatch(
    ellmer::Turn("user", list(ellmer::ContentText("ts test"))),
    error = function(e) NULL)
  if (is.null(user_turn)) skip("ellmer Turn API not available")
  tryCatch(chat$set_turns(list(user_turn)),
           error = function(e) skip("set_turns failed"))

  sid <- save_session(chat, cwd = tmp_dir)
  session_dir  <- codeagent:::.get_project_session_dir(tmp_dir)
  session_file <- file.path(session_dir, paste0(sid, ".jsonl"))

  first_line <- readLines(session_file, n = 1L, warn = FALSE)
  hdr <- jsonlite::fromJSON(first_line, simplifyVector = FALSE)
  ts  <- hdr[["timestamp"]]

  # Must match ISO 8601 with milliseconds: YYYY-MM-DDTHH:MM:SS.mmmZ
  expect_match(ts, "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}\\.\\d+Z$")
})
