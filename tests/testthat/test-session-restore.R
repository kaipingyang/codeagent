# tests/testthat/test-session-restore.R
# Tests for restore_session_into_chat (harness, shared by CLI --continue/--resume).

library(ellmer)

test_that("restore_session_into_chat resumes a specific session by id", {
  tmp <- withr::local_tempdir()
  ch  <- chat_anthropic(model = "claude-sonnet-4-6")
  ch$set_turns(list(Turn("user", "alpha"), Turn("assistant", "beta")))
  sid <- save_session(ch, cwd = tmp)

  ch2 <- chat_anthropic(model = "claude-sonnet-4-6")
  out <- restore_session_into_chat(ch2, session_id = sid, cwd = tmp)

  expect_identical(out, sid)
  expect_length(ch2$get_turns(), 2L)
  expect_identical(ch2$get_turns()[[1]]@contents[[1]]@text, "alpha")
})

test_that("restore_session_into_chat with NULL id continues the most recent session", {
  tmp <- withr::local_tempdir()
  ch1 <- chat_anthropic(model = "claude-sonnet-4-6")
  ch1$set_turns(list(Turn("user", "older")))
  save_session(ch1, cwd = tmp)
  Sys.sleep(1.1)  # ensure distinct mtime
  ch2 <- chat_anthropic(model = "claude-sonnet-4-6")
  ch2$set_turns(list(Turn("user", "newest"), Turn("assistant", "reply")))
  sid2 <- save_session(ch2, cwd = tmp)

  ch3 <- chat_anthropic(model = "claude-sonnet-4-6")
  out <- restore_session_into_chat(ch3, session_id = NULL, cwd = tmp)

  expect_identical(out, sid2)                     # most recent
  expect_identical(ch3$get_turns()[[1]]@contents[[1]]@text, "newest")
})

test_that("restore_session_into_chat returns NULL when no session exists", {
  tmp <- withr::local_tempdir()
  ch  <- chat_anthropic(model = "claude-sonnet-4-6")
  out <- restore_session_into_chat(ch, session_id = NULL, cwd = tmp)
  expect_null(out)
  expect_length(ch$get_turns(), 0L)
})

test_that("replay migration updates only a presentation copy", {
  tool <- ellmer::tool(function(x) x, name = "fixture_tool",
                       description = "fixture tool",
                       arguments = list(x = ellmer::type_string("x")))
  req <- ContentToolRequest(id = "req-legacy", name = "fixture_tool",
                            arguments = list(x = "x"), tool = tool)
  fixture <- jsonlite::fromJSON(
    test_path("fixtures", "sessions", "legacy-display.json"),
    simplifyVector = FALSE)
  legacy <- ContentToolResult(
    value = fixture$value, request = req,
    extra = list(display = fixture$display))
  chat <- chat_anthropic(model = "fixture")
  chat$register_tool(tool)
  chat$set_turns(list(Turn("user", contents = list(legacy))))

  replay_chat <- .presentation_chat_for_replay(chat)
  original <- chat$get_turns()[[1L]]@contents[[1L]]
  migrated <- replay_chat$get_turns()[[1L]]@contents[[1L]]

  expect_false(identical(replay_chat, chat))
  expect_false(is.null(original@extra$display$toolcard))
  expect_null(migrated@extra$display$toolcard)
  expect_null(migrated@extra$display$right_output)
  expect_s3_class(migrated@extra$display, "shinychat_tool_result_display")
  expect_identical(as.character(migrated@value), "provider value")
  expect_identical(migrated@request@id, "req-legacy")
  expect_identical(length(chat$get_turns()), length(replay_chat$get_turns()))
})

test_that("replay migration safely degrades malformed display records", {
  malformed <- ContentToolResult(value = "safe text",
    extra = list(display = list(toolcard = list(kind = "unknown"))))
  turns <- list(Turn("user", contents = list(malformed)))
  migrated <- expect_no_error(.migrate_replay_turns(turns))
  result <- migrated[[1L]]@contents[[1L]]
  expect_identical(as.character(result@value), "safe text")
  expect_null(result@extra$display$toolcard)
  expect_s3_class(result@extra$display, "shinychat_tool_result_display")
})

test_that(".replay_turns_to_ui skips empty assistant turns (no stuck '...' on restore)", {
  rendered <- list()
  testthat::with_mocked_bindings(
    {
      codeagent:::.replay_turns_to_ui(chat = NULL, session = NULL)
    },
    contents_shinychat = function(chat) list(
      list(role = "user",      content = "hello"),
      list(role = "assistant", content = ""),                    # empty -> skip
      list(role = "assistant", content = "Real answer"),         # keep
      list(role = "assistant", content = list("", "block2")),    # filter -> single block
      list(role = "assistant", content = list("", "   "))        # all empty -> skip
    ),
    chat_append_message = function(id, msg, chunk = FALSE, session = NULL) {
      rendered[[length(rendered) + 1L]] <<-
        list(role = msg$role, content = msg$content, chunk = chunk)
      invisible()
    },
    .package = "shinychat"
  )
  # Only the 3 non-empty messages render; no empty assistant bubbles.
  expect_length(rendered, 3L)
  contents <- vapply(rendered, function(r) {
    if (is.character(r$content)) r$content else paste(unlist(r$content), collapse = "")
  }, character(1))
  expect_setequal(contents, c("hello", "Real answer", "block2"))
  # The surviving single-block turn must be a complete message (chunk = FALSE),
  # never a dangling "start" that leaves the bubble streaming forever.
  expect_true(all(vapply(rendered, function(r) identical(r$chunk, FALSE), logical(1))))
})
