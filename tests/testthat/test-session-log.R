# tests/testthat/test-session-log.R
# Session files as an append-only log (format_version 2): turns are appended,
# a context change (compaction, rewind, clear) appends a compact_boundary with
# a snapshot of the new context. The model context restores from the last
# boundary; the display keeps every turn.

library(ellmer)

.log_chat <- function() chat_openai_compatible(base_url = "http://127.0.0.1:1", model = "m",
                                               credentials = function() "k")
.log_env <- function(env = parent.frame()) {
  withr::local_envvar(CODEAGENT_HOME = withr::local_tempdir(.local_envir = env), .local_envir = env)
  withr::local_tempdir(.local_envir = env)   # cwd
}
.texts <- function(turns) vapply(turns, function(t) paste(vapply(t@contents, function(x)
  tryCatch(x@text, error = function(e) ""), ""), collapse = ""), "")
.entries <- function(sid, cwd) {
  lines <- readLines(.find_session_path(sid, cwd), warn = FALSE)
  lapply(lines, jsonlite::fromJSON, simplifyVector = FALSE)
}

test_that("each save appends only the new turns", {
  cwd <- .log_env()
  ch <- .log_chat()
  ch$set_turns(list(Turn("user", "q1"), Turn("assistant", "a1")))
  sid <- save_session(ch, cwd)
  ch$set_turns(c(ch$get_turns(), list(Turn("user", "q2"), Turn("assistant", "a2"))))
  save_session(ch, cwd, sid)
  save_session(ch, cwd, sid)                                   # nothing new: nothing appended
  e <- .entries(sid, cwd)
  types <- vapply(e, `[[`, "", "type")
  expect_identical(types[1], "session-start")
  expect_identical(e[[1]]$format_version, 2L)
  expect_identical(sum(types %in% c("user", "assistant")), 4L)
  # uuid chain
  turns <- e[types %in% c("user", "assistant")]
  expect_identical(turns[[2]]$parentUuid, turns[[1]]$uuid)
})

test_that("after compaction the display keeps every turn and the model context starts at the boundary", {
  cwd <- .log_env()
  ch <- .log_chat()
  ch$set_turns(list(Turn("user", "q1"), Turn("assistant", "a1"), Turn("user", "q2"), Turn("assistant", "a2")))
  sid <- save_session(ch, cwd)
  # compaction: history replaced by a summary, then the next exchange
  ch$set_turns(list(Turn("user", "Summary:\nq1/a1/q2/a2")))
  .session_sync_context(ch, cwd, sid, context_event = "compact")
  ch$set_turns(c(ch$get_turns(), list(Turn("user", "q3"), Turn("assistant", "a3"))))
  save_session(ch, cwd, sid)

  model <- .log_chat(); restore_session_into_chat(model, sid, cwd)
  expect_identical(.texts(model$get_turns()), c("Summary:\nq1/a1/q2/a2", "q3", "a3"))

  shown <- .read_session_display_turns(sid, cwd)
  expect_identical(.texts(shown$turns), c("q1", "a1", "q2", "a2", "q3", "a3"))
  expect_identical(shown$boundaries, 4L)                        # compacted after the 4th shown turn

  e <- .entries(sid, cwd)
  b <- Filter(function(x) identical(x$subtype, "compact_boundary"), e)
  expect_length(b, 1L)
  expect_null(b[[1]]$parentUuid)
  expect_false(is.null(b[[1]]$logicalParentUuid))
  expect_identical(b[[1]]$compactMetadata$trigger, "compact")
  expect_identical(b[[1]]$compactMetadata$preTurns, 4L)
  expect_identical(b[[1]]$compactMetadata$postTurns, 1L)
})

test_that("a compaction seen only at the end-of-turn save still keeps the new reply", {
  cwd <- .log_env()
  ch <- .log_chat()
  ch$set_turns(list(Turn("user", "q1"), Turn("assistant", "a1")))
  sid <- save_session(ch, cwd)
  ch$set_turns(list(Turn("user", "Summary:\nq1/a1"), Turn("user", "q2"), Turn("assistant", "a2")))
  save_session(ch, cwd, sid)                                  # no sync call in between
  shown <- .read_session_display_turns(sid, cwd)
  expect_identical(.texts(shown$turns), c("q1", "a1", "q2", "a2"))   # summary is not shown
  model <- .log_chat(); restore_session_into_chat(model, sid, cwd)
  expect_identical(.texts(model$get_turns()), c("Summary:\nq1/a1", "q2", "a2"))
})

test_that("rewind and clear hide the removed turns from the display", {
  cwd <- .log_env()
  ch <- .log_chat()
  ch$set_turns(list(Turn("user", "q1"), Turn("assistant", "a1"), Turn("user", "q2"), Turn("assistant", "a2")))
  sid <- save_session(ch, cwd)
  truncate_chat_turns(ch, 2L)
  ch$set_turns(c(ch$get_turns(), list(Turn("user", "q2b"), Turn("assistant", "a2b"))))
  save_session(ch, cwd, sid)
  expect_identical(.texts(.read_session_display_turns(sid, cwd)$turns), c("q1", "a1", "q2b", "a2b"))
  b <- Filter(function(x) identical(x$subtype, "compact_boundary"), .entries(sid, cwd))
  expect_identical(b[[1]]$compactMetadata$trigger, "rewind")

  ch$set_turns(list())
  .session_sync_context(ch, cwd, sid)
  ch$set_turns(list(Turn("user", "fresh"), Turn("assistant", "start")))
  save_session(ch, cwd, sid)
  expect_identical(.texts(.read_session_display_turns(sid, cwd)$turns), c("fresh", "start"))
  model <- .log_chat(); restore_session_into_chat(model, sid, cwd)
  expect_identical(.texts(model$get_turns()), c("fresh", "start"))
})

test_that("tool calls survive in both the model context and the display", {
  cwd <- .log_env()
  ch <- .log_chat()
  req <- ContentToolRequest(id = "c1", name = "Host", arguments = list(k = "v"))
  res <- ContentToolResult(value = "ok", request = req,
                           extra = list(display = list(title = "Card", html = htmltools::div("x"))))
  ch$set_turns(list(Turn("user", "go"), Turn("assistant", list(req)), Turn("user", list(res)), Turn("assistant", "done")))
  sid <- save_session(ch, cwd)
  model <- .log_chat(); restore_session_into_chat(model, sid, cwd)
  r <- model$get_turns()[[3]]@contents[[1]]
  expect_s3_class(r, "ellmer::ContentToolResult")
  expect_identical(r@extra$display$title, "Card")
  shown <- .read_session_display_turns(sid, cwd)
  expect_s3_class(shown$turns[[2]]@contents[[1]], "ellmer::ContentToolRequest")
})

test_that("a renamed session keeps its title across later saves", {
  cwd <- .log_env()
  ch <- .log_chat()
  ch$set_turns(list(Turn("user", "q1"), Turn("assistant", "a1")))
  sid <- save_session(ch, cwd)
  rename_session(sid, "My analysis", directory = cwd)
  ch$set_turns(c(ch$get_turns(), list(Turn("user", "q2"), Turn("assistant", "a2"))))
  save_session(ch, cwd, sid)
  expect_identical(get_session_info(sid, cwd)$summary, "My analysis")
})

test_that("a version 1 file is read as before and migrated on the next save", {
  cwd <- .log_env()
  ch <- .log_chat()
  ch$set_turns(list(Turn("user", "old q"), Turn("assistant", "old a")))
  sid <- .generate_uuid_v4()
  path <- file.path(.ensure_session_dir(cwd), paste0(sid, ".jsonl"))
  now <- "2026-01-01T00:00:00.000Z"
  writeLines(c(
    jsonlite::toJSON(list(type = "session-start", sessionId = sid, cwd = cwd, timestamp = now,
                          model = "m", format_version = 1L), auto_unbox = TRUE),
    jsonlite::toJSON(list(type = "chat-state", sessionId = sid, timestamp = now,
                          state = .session_state_encode(ch)), auto_unbox = TRUE),
    jsonlite::toJSON(list(type = "user", uuid = "u1", sessionId = sid, timestamp = now,
                          message = list(role = "user", content = "old q")), auto_unbox = TRUE),
    jsonlite::toJSON(list(type = "assistant", uuid = "u2", sessionId = sid, timestamp = now,
                          message = list(role = "assistant", content = "old a")), auto_unbox = TRUE),
    jsonlite::toJSON(list(type = "custom-title", customTitle = "Legacy title", sessionId = sid), auto_unbox = TRUE)),
    path)
  model <- .log_chat(); restore_session_into_chat(model, sid, cwd)
  expect_identical(.texts(model$get_turns()), c("old q", "old a"))
  expect_identical(.texts(.read_session_display_turns(sid, cwd)$turns), c("old q", "old a"))
  ch$set_turns(c(ch$get_turns(), list(Turn("user", "new q"), Turn("assistant", "new a"))))
  save_session(ch, cwd, sid)
  e <- .entries(sid, cwd)
  expect_identical(e[[1]]$format_version, 2L)
  expect_identical(.texts(.read_session_display_turns(sid, cwd)$turns), c("old q", "old a", "new q", "new a"))
  expect_identical(get_session_info(sid, cwd)$summary, "Legacy title")
})

test_that("a partly written last line is skipped and the turn is written again", {
  cwd <- .log_env()
  ch <- .log_chat()
  ch$set_turns(list(Turn("user", "q1"), Turn("assistant", "a1")))
  sid <- save_session(ch, cwd)
  cat("{\"type\":\"user\",\"uuid\":\"broken", file = .find_session_path(sid, cwd), append = TRUE)
  ch$set_turns(c(ch$get_turns(), list(Turn("user", "q2"), Turn("assistant", "a2"))))
  save_session(ch, cwd, sid)
  expect_identical(.texts(.read_session_display_turns(sid, cwd)$turns), c("q1", "a1", "q2", "a2"))
  model <- .log_chat(); restore_session_into_chat(model, sid, cwd)
  expect_length(model$get_turns(), 4L)
})

test_that("the canvas line is appended only when it changes", {
  cwd <- .log_env()
  ch <- .log_chat()
  ch$set_turns(list(Turn("user", "q1"), Turn("assistant", "a1")))
  sid <- save_session(ch, cwd, genui_state = list(v = 1))
  save_session(ch, cwd, sid, genui_state = list(v = 1))
  save_session(ch, cwd, sid, genui_state = list(v = 2))
  types <- vapply(.entries(sid, cwd), `[[`, "", "type")
  expect_identical(sum(types == "genui-state"), 2L)
  expect_identical(.read_session_genui_state(sid, cwd)$v, 2L)
})

test_that("restoring from the list replays every shown turn, gated, with a note at the compaction", {
  cwd <- .log_env()
  ch <- .log_chat()
  ch$set_turns(list(Turn("user", "q1"), Turn("assistant", "a1 with BGB-001-0007")))
  sid <- save_session(ch, cwd)
  ch$set_turns(list(Turn("user", "Summary:\nq1/a1")))
  .session_sync_context(ch, cwd, sid, "compact")
  ch$set_turns(c(ch$get_turns(), list(Turn("user", "q2"), Turn("assistant", "a2"))))
  save_session(ch, cwd, sid)
  shield <- DataShield$new(strategies = list(shield_egress()))
  shield$register_data(data.frame(USUBJID = sprintf("BGB-001-%04d", 1:20)), name = "adsl",
                       sensitivity = c(USUBJID = "identifier"))
  live <- .log_chat(); attr(live, "codeagent_data_shield") <- shield
  sent <- list()
  local_mocked_bindings(chat_append_message = function(id, msg, ...) { sent[[length(sent) + 1L]] <<- msg; invisible() },
                        .package = "shinychat")
  .replay_display_to_ui(live, sid, cwd, session = NULL, settings = list())
  txt <- vapply(sent, function(m) paste(unlist(m$content), collapse = " "), "")
  expect_true(any(grepl("q1", txt)) && any(grepl("q2", txt)))
  expect_true(any(grepl("compacted", txt)))
  expect_false(any(grepl("BGB-001-0007", txt, fixed = TRUE)))        # output gate applied
  expect_false(any(grepl("Summary:", txt, fixed = TRUE)))
})
