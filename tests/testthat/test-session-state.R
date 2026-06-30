# tests/testthat/test-session-state.R
# Tests for lossless session persistence (M7: contents_record/replay round-trip).

library(ellmer)

test_that("session save/restore preserves tool-call turns losslessly", {
  tmp <- withr::local_tempdir()
  wt  <- tool(function(city) paste("sunny", city), "weather",
              arguments = list(city = type_string("c")))
  ch  <- chat_anthropic(model = "claude-sonnet-4-6")
  ch$register_tool(wt)
  req <- ContentToolRequest(id = "c1", name = "weather",
                            arguments = list(city = "NYC"))
  res <- ContentToolResult(value = "sunny NYC", request = req)
  ch$set_turns(list(
    Turn("user", "weather?"),
    Turn("assistant", contents = list(req)),
    Turn("user", contents = list(res))
  ))
  sid <- save_session(ch, cwd = tmp)

  ch2 <- chat_anthropic(model = "claude-sonnet-4-6")
  ch2$register_tool(wt)
  restore_session_into_chat(ch2, session_id = sid, cwd = tmp)

  t <- ch2$get_turns()
  expect_length(t, 3L)
  expect_identical(t[[2]]@contents[[1]]@name, "weather")
  expect_identical(t[[2]]@contents[[1]]@arguments$city, "NYC")
  expect_identical(as.character(t[[3]]@contents[[1]]@value), "sunny NYC")
  expect_identical(t[[3]]@contents[[1]]@request@id, "c1")
})

test_that("save_session writes a chat-state line", {
  tmp <- withr::local_tempdir()
  ch  <- chat_anthropic(model = "claude-sonnet-4-6")
  ch$set_turns(list(Turn("user", "hi"), Turn("assistant", "hello")))
  sid <- save_session(ch, cwd = tmp)

  st <- codeagent:::.read_session_state(sid, tmp)
  expect_false(is.null(st))
  expect_length(st, 2L)
})

test_that("restore falls back to text turns for legacy sessions (no chat-state)", {
  tmp <- withr::local_tempdir()
  # Hand-write a legacy session file with only text lines (no chat-state).
  dir <- codeagent:::.ensure_session_dir(tmp)
  sid <- "legacy01-0000-0000-0000-000000000000"
  fp  <- file.path(dir, paste0(sid, ".jsonl"))
  writeLines(c(
    jsonlite::toJSON(list(type = "session-start", sessionId = sid,
                          cwd = tmp, timestamp = "2026-01-01T00:00:00Z",
                          format_version = 1L), auto_unbox = TRUE),
    jsonlite::toJSON(list(type = "user", uuid = "u1", sessionId = sid,
                          message = list(role = "user", content = "legacy q")),
                     auto_unbox = TRUE),
    jsonlite::toJSON(list(type = "assistant", uuid = "a1", sessionId = sid,
                          message = list(role = "assistant", content = "legacy a")),
                     auto_unbox = TRUE)
  ), fp)

  expect_null(codeagent:::.read_session_state(sid, tmp))  # no lossless line
  ch <- chat_anthropic(model = "claude-sonnet-4-6")
  restore_session_into_chat(ch, session_id = sid, cwd = tmp)
  t <- ch$get_turns()
  expect_length(t, 2L)
  expect_identical(t[[1]]@contents[[1]]@text, "legacy q")
})

test_that(".session_state_encode/decode round-trips through JSON", {
  ch <- chat_anthropic(model = "claude-sonnet-4-6")
  ch$set_turns(list(Turn("user", "a"), Turn("assistant", "b")))
  enc <- codeagent:::.session_state_encode(ch)
  expect_type(enc, "character")
  dec <- codeagent:::.session_state_decode(enc)
  expect_length(dec, 2L)
})
