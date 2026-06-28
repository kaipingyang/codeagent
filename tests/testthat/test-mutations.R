test_that("rename_session appends a custom-title entry", {
  tmp_dir     <- withr::local_tempdir()
  session_dir <- codeagent:::.ensure_session_dir(tmp_dir)
  sid         <- codeagent:::.generate_uuid_v4()
  hdr <- jsonlite::toJSON(list(type = "session-start", sessionId = sid,
                                cwd = tmp_dir, timestamp = "2026-01-01T00:00:00Z",
                                model = "test"), auto_unbox = TRUE)
  writeLines(hdr, file.path(session_dir, paste0(sid, ".jsonl")))

  rename_session(sid, "My Cool Session", directory = tmp_dir)

  lines <- readLines(file.path(session_dir, paste0(sid, ".jsonl")))
  last  <- jsonlite::fromJSON(lines[length(lines)], simplifyVector = FALSE)
  expect_equal(last$type, "custom-title")
  expect_equal(last$customTitle, "My Cool Session")
})

test_that("rename_session rejects empty title", {
  expect_error(rename_session(codeagent:::.generate_uuid_v4(), "  "),
               "non-empty")
})

test_that("rename_session rejects invalid UUID", {
  expect_error(rename_session("not-a-uuid", "Title"), "Invalid session_id")
})

test_that("tag_session appends a tag entry", {
  tmp_dir     <- withr::local_tempdir()
  session_dir <- codeagent:::.ensure_session_dir(tmp_dir)
  sid         <- codeagent:::.generate_uuid_v4()
  hdr <- jsonlite::toJSON(list(type = "session-start", sessionId = sid,
                                cwd = tmp_dir, timestamp = "2026-01-01T00:00:00Z",
                                model = "test"), auto_unbox = TRUE)
  writeLines(hdr, file.path(session_dir, paste0(sid, ".jsonl")))

  tag_session(sid, "important", directory = tmp_dir)

  lines <- readLines(file.path(session_dir, paste0(sid, ".jsonl")))
  last  <- jsonlite::fromJSON(lines[length(lines)], simplifyVector = FALSE)
  expect_equal(last$type, "tag")
  expect_equal(last$tag, "important")
})

test_that("tag_session truncates tags that are too long", {
  tmp_dir     <- withr::local_tempdir()
  session_dir <- codeagent:::.ensure_session_dir(tmp_dir)
  sid         <- codeagent:::.generate_uuid_v4()
  hdr <- jsonlite::toJSON(list(type = "session-start", sessionId = sid,
                                cwd = tmp_dir, timestamp = "2026-01-01T00:00:00Z",
                                model = "test"), auto_unbox = TRUE)
  writeLines(hdr, file.path(session_dir, paste0(sid, ".jsonl")))

  long_tag <- paste(rep("x", 200L), collapse = "")
  tag_session(sid, long_tag, directory = tmp_dir)

  lines <- readLines(file.path(session_dir, paste0(sid, ".jsonl")))
  last  <- jsonlite::fromJSON(lines[length(lines)], simplifyVector = FALSE)
  expect_lte(nchar(last$tag), .MAX_SESSION_TAG_LEN)
})

test_that("delete_session removes the file", {
  tmp_dir     <- withr::local_tempdir()
  session_dir <- codeagent:::.ensure_session_dir(tmp_dir)
  sid         <- codeagent:::.generate_uuid_v4()
  path        <- file.path(session_dir, paste0(sid, ".jsonl"))
  writeLines("{}", path)
  expect_true(file.exists(path))

  delete_session(sid, directory = tmp_dir)
  expect_false(file.exists(path))
})

test_that("delete_session errors when session not found", {
  expect_error(
    delete_session(codeagent:::.generate_uuid_v4(),
                   directory = withr::local_tempdir()),
    "not found"
  )
})

test_that("fork_session creates an independent copy with a new UUID", {
  tmp_dir     <- withr::local_tempdir()
  session_dir <- codeagent:::.ensure_session_dir(tmp_dir)
  sid         <- codeagent:::.generate_uuid_v4()
  hdr <- jsonlite::toJSON(list(type = "session-start", sessionId = sid,
                                cwd = tmp_dir, timestamp = "2026-01-01T00:00:00Z",
                                model = "test"), auto_unbox = TRUE)
  writeLines(c(hdr, '{"type":"user","message":{"role":"user","content":"hi"}}'),
             file.path(session_dir, paste0(sid, ".jsonl")))

  new_sid <- fork_session(sid, directory = tmp_dir)

  # New UUID is different
  expect_false(identical(new_sid, sid))
  expect_true(nzchar(codeagent:::.validate_uuid(new_sid) %||% ""))

  # New file exists
  expect_true(file.exists(file.path(session_dir, paste0(new_sid, ".jsonl"))))

  # Fork record has session-fork type with correct sourceId
  lines     <- readLines(file.path(session_dir, paste0(new_sid, ".jsonl")))
  fork_hdr  <- jsonlite::fromJSON(lines[1L], simplifyVector = FALSE)
  expect_equal(fork_hdr$type,     "session-fork")
  expect_equal(fork_hdr$sourceId, sid)

  # Regression: timestamp must be valid ISO 8601 (decimal point preserved)
  # Bug: sub('\\\\.',...) was stripping the decimal point from the timestamp.
  ts <- fork_hdr[["timestamp"]]
  expect_match(ts, "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}\\.\\d+Z$")
})
