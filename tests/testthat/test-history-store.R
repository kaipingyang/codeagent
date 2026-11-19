# tests/testthat/test-history-store.R
# .SessionLogStore: shinychat history over codeagent's session log (read side).

library(ellmer)

local_store_env <- function(env = parent.frame()) {
  home <- withr::local_tempdir(.local_envir = env)
  proj <- withr::local_tempdir(.local_envir = env)
  withr::local_envvar(CODEAGENT_HOME = home, .local_envir = env)
  proj
}

save_fixture <- function(proj, turns, title = NULL) {
  ch <- chat_anthropic(model = "claude-sonnet-4-6")
  ch$set_turns(turns)
  save_session(ch, cwd = proj, title = title)
}

set_owner <- function(proj, sid, user) {
  path <- .find_session_path(sid, proj)
  lines <- readLines(path)
  hdr <- jsonlite::fromJSON(lines[[1]], simplifyVector = FALSE)
  hdr$user <- user
  lines[[1]] <- as.character(jsonlite::toJSON(hdr, auto_unbox = TRUE))
  writeLines(lines, path)
}

part <- function(scope = .history_local_user())
  structure(list(chat_id = "chat", scope = scope),
            class = "shinychat_conversation_partition")

bound_store <- function(proj, settings = list()) {
  st <- .SessionLogStore$new(cwd = proj)
  st$bind(chat_anthropic(model = "claude-sonnet-4-6"), settings)
  st
}

test_that("the store is a shinychat ConversationStore", {
  proj <- local_store_env()
  expect_true(inherits(.SessionLogStore$new(cwd = proj), "ConversationStore"))
})

test_that("list() shows the project's earlier sessions, newest first", {
  proj <- local_store_env()
  a <- save_fixture(proj, list(Turn("user", "first question"), Turn("assistant", "a1")))
  Sys.sleep(1.1)
  b <- save_fixture(proj, list(Turn("user", "second question"), Turn("assistant", "b1")))
  metas <- .SessionLogStore$new(cwd = proj)$list(part())
  expect_identical(vapply(metas, `[[`, "", "id"), c(b, a))
  expect_identical(metas[[2]]$title, "first question")
  expect_true(all(vapply(metas, function(m) is.double(m$size_bytes) && m$size_bytes > 0, NA)))
  expect_match(metas[[1]]$created_at, "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z$")
})

test_that("list() uses a custom title and leaves out sessions with nothing said", {
  proj <- local_store_env()
  sid <- save_fixture(proj, list(Turn("user", "q"), Turn("assistant", "r")))
  rename_session(sid, "Named by me", directory = proj)
  save_fixture(proj, list())
  metas <- .SessionLogStore$new(cwd = proj)$list(part())
  expect_length(metas, 1L)
  expect_identical(metas[[1]]$title, "Named by me")
})

test_that("sessions are partitioned by owner; unowned ones belong to the local account", {
  proj <- local_store_env()
  mine <- save_fixture(proj, list(Turn("user", "mine"), Turn("assistant", "r")))
  bobs <- save_fixture(proj, list(Turn("user", "bob's"), Turn("assistant", "r")))
  set_owner(proj, bobs, "bob")
  st <- bound_store(proj)
  expect_identical(vapply(st$list(part()), `[[`, "", "id"), mine)
  expect_identical(vapply(st$list(part("bob")), `[[`, "", "id"), bobs)
  expect_null(st$get(part(), bobs))
  expect_null(st$get(part("bob"), mine))
})

test_that("get() needs a bound store", {
  proj <- local_store_env()
  sid <- save_fixture(proj, list(Turn("user", "q"), Turn("assistant", "r")))
  expect_null(.SessionLogStore$new(cwd = proj)$get(part(), sid))
})

test_that("get() returns a linear record of the turns as shown", {
  proj <- local_store_env()
  req <- ContentToolRequest(id = "t1", name = "Read", arguments = list(path = "x.R"))
  turns <- list(
    Turn("user", "<system-reminder>ctx</system-reminder>\nread x.R"),
    Turn("assistant", list(req)),
    Turn("user", list(ContentToolResult(value = "x <- 1", request = req))),
    Turn("assistant", "It assigns 1."),
    Turn("user", "thanks"),
    Turn("assistant", "You're welcome."))
  sid <- save_fixture(proj, turns)
  rec <- bound_store(proj)$get(part(), sid)

  expect_identical(rec$schema_version, 1L)
  expect_identical(rec$id, sid)
  expect_identical(rec$values$codeagent_session_id, sid)
  expect_identical(rec$response_count, 2L)
  # user | assistant + tool result + assistant | user | assistant
  expect_identical(names(rec$nodes), sprintf("n_%04d", 1:4))
  expect_identical(lengths(lapply(rec$nodes, `[[`, "turns")), c(n_0001 = 1L, n_0002 = 3L, n_0003 = 1L, n_0004 = 1L))
  expect_identical(rec$current_leaf, "n_0004")
  expect_null(rec$nodes$n_0001$parent)
  expect_identical(rec$nodes$n_0002$parent, "n_0001")
  expect_identical(rec$nodes$n_0001$children, list("n_0002"))
  expect_true(all(vapply(rec$nodes, function(n) is.null(n$ui), NA)))
  # the record's turns are shinychat's stored form and replay
  first <- contents_replay(rec$nodes$n_0001$turns[[1]])
  expect_identical(first@contents[[1]]@text, "read x.R")
})

test_that("get() gates what it returns with the session's Data Shield", {
  proj <- local_store_env()
  sid <- save_fixture(proj, list(Turn("user", "q"), Turn("assistant", "secret 123-45-6789")))
  shield <- structure(list(), class = "DataShield")   # broken shield: gate fails closed
  rec <- bound_store(proj, list(data_shield_engine = shield))$get(part(), sid)
  last <- contents_replay(rec$nodes[[rec$current_leaf]]$turns[[1]])
  expect_false(grepl("123-45-6789", last@contents[[1]]@text, fixed = TRUE))
})

test_that("get() shows the text of an early log that has no turn records", {
  proj <- local_store_env()
  sid <- .generate_uuid_v4()
  dir <- .ensure_session_dir(proj)
  line <- function(x) as.character(jsonlite::toJSON(x, auto_unbox = TRUE))
  writeLines(c(
    line(list(type = "session-start", sessionId = sid, cwd = proj,
              timestamp = "2026-06-27T10:00:00.000Z", format_version = 1L)),
    line(list(type = "user", uuid = "u1", sessionId = sid, message = list(role = "user", content = "early question"))),
    line(list(type = "assistant", uuid = "a1", sessionId = sid, message = list(role = "assistant", content = ""))),
    line(list(type = "assistant", uuid = "a2", sessionId = sid, message = list(role = "assistant", content = "early answer")))),
    file.path(dir, paste0(sid, ".jsonl")))
  rec <- bound_store(proj)$get(part(), sid)
  expect_identical(names(rec$nodes), c("n_0001", "n_0002"))
  expect_identical(contents_replay(rec$nodes$n_0002$turns[[1]])@contents[[1]]@text, "early answer")
})

test_that("ids that are not this project's sessions resolve to nothing", {
  proj <- local_store_env()
  other <- withr::local_tempdir()
  theirs <- save_fixture(other, list(Turn("user", "q"), Turn("assistant", "r")))
  st <- bound_store(proj)
  for (id in list(theirs, "../x", "c_zz", "c_0123456789abc", NA_character_, 1L, c("a", "b")))
    expect_null(st$get(part(), id))
})

new_record <- function(sid, id = "c_00001a2b3c4d5e6f7a8b9", title = "New chat",
                       title_source = NULL) {
  list(schema_version = 1L, id = id, title = title, title_source = title_source,
       response_count = 1L, created_at = "2026-11-19T10:00:00Z",
       updated_at = "2026-11-19T10:00:00Z", client_info = list(),
       nodes = list(n_0001 = list(parent = NULL, children = list(),
                                  turns = list(contents_record(Turn("user", "x"))), ui = NULL)),
       current_leaf = "n_0001", values = list(codeagent_session_id = sid),
       bookmark_state_id = NULL)
}

test_that("put() never writes turns; it records the shinychat id and titles", {
  proj <- local_store_env()
  sid <- save_fixture(proj, list(Turn("user", "q"), Turn("assistant", "r")))
  path <- .find_session_path(sid, proj)
  n_before <- length(readLines(path))
  st <- bound_store(proj)
  rec <- new_record(sid)
  st$put(part(), rec)                      # fallback title: nothing to say
  st$put(part(), rec)
  lines <- readLines(path)
  expect_length(lines, n_before + 1L)      # one shinychat-record line, once
  expect_match(lines[[length(lines)]], "\"type\":\"shinychat-record\"", fixed = TRUE)

  metas <- st$list(part())
  expect_identical(metas[[1]]$id, rec$id)  # the id shinychat holds as active
  expect_identical(st$get(part(), rec$id)$values$codeagent_session_id, sid)
  expect_identical(st$get(part(), rec$id)$id, rec$id)
  expect_false(any(grepl("\"type\":\"(user|assistant)\"", lines[-seq_len(n_before)])))
})

test_that("a rename wins over a later model title", {
  proj <- local_store_env()
  sid <- save_fixture(proj, list(Turn("user", "q"), Turn("assistant", "r")))
  st <- bound_store(proj)
  st$put(part(), new_record(sid, title = "Model title", title_source = "llm"))
  expect_identical(st$list(part())[[1]]$title, "Model title")
  st$put(part(), new_record(sid, title = "My name", title_source = "user"))
  st$put(part(), new_record(sid, title = "Model again", title_source = "llm"))
  expect_identical(st$list(part())[[1]]$title, "My name")
  rec <- st$get(part(), sid)
  expect_identical(rec$title_source, "user")
})

test_that("an earlier session reopened after two replies keeps its count", {
  proj <- local_store_env()
  sid <- save_fixture(proj, list(Turn("user", "a"), Turn("assistant", "b"),
                                 Turn("user", "c"), Turn("assistant", "d")))
  expect_identical(bound_store(proj)$get(part(), sid)$response_count, 2L)
})

test_that("a new conversation is listed before its log exists, then written", {
  proj <- local_store_env()
  st <- bound_store(proj)
  sid <- .generate_uuid_v4()
  rec <- new_record(sid, title = "fresh question")
  st$put(part(), rec)
  expect_null(.find_session_path(sid, proj))
  metas <- st$list(part())
  expect_identical(vapply(metas, `[[`, "", "id"), rec$id)
  expect_length(st$list(part("bob")), 0L)

  ch <- chat_anthropic(model = "claude-sonnet-4-6")
  attr(ch, "codeagent_history_owner") <- .history_local_user()
  ch$set_turns(list(Turn("user", "fresh question"), Turn("assistant", "r")))
  save_session(ch, cwd = proj, session_id = sid)
  metas <- st$list(part())
  expect_length(metas, 1L)
  expect_identical(metas[[1]]$id, rec$id)
  expect_identical(get_session_info(sid, proj)$shinychat_id, rec$id)
  expect_identical(get_session_info(sid, proj)$user, .history_local_user())
})

test_that("a new conversation's record id reaches its log through the Chat, across store instances", {
  proj <- local_store_env()
  ch <- chat_anthropic(model = "claude-sonnet-4-6")
  attr(ch, "codeagent_history_owner") <- .history_local_user()
  st <- .SessionLogStore$new(cwd = proj)$bind(ch, list())
  sid <- .generate_uuid_v4()
  rec <- new_record(sid, title = "Named early", title_source = "user")
  st$put(part(), rec)                              # before the log exists
  ch$set_turns(list(Turn("user", "q"), Turn("assistant", "r")))
  save_session(ch, cwd = proj, session_id = sid)   # creates the log

  fresh <- bound_store(proj)                       # a reload: new store, empty memory
  metas <- fresh$list(part())
  expect_identical(metas[[1]]$id, rec$id)
  expect_identical(metas[[1]]$title, "Named early")
  got <- fresh$get(part(), rec$id)
  expect_identical(got$id, rec$id)
  expect_identical(got$values$codeagent_session_id, sid)

  # the next conversation in the same Chat does not inherit it
  sid2 <- .generate_uuid_v4()
  ch$set_turns(list(Turn("user", "other"), Turn("assistant", "r")))
  save_session(ch, cwd = proj, session_id = sid2)
  expect_null(get_session_info(sid2, proj)$shinychat_id)
})

test_that("save_session() writes the history owner into a new log's header", {
  proj <- local_store_env()
  ch <- chat_anthropic(model = "claude-sonnet-4-6")
  attr(ch, "codeagent_history_owner") <- "alice"
  ch$set_turns(list(Turn("user", "q"), Turn("assistant", "r")))
  sid <- save_session(ch, cwd = proj)
  expect_identical(get_session_info(sid, proj)$user, "alice")
  expect_identical(vapply(.SessionLogStore$new(cwd = proj)$list(part("alice")), `[[`, "", "id"), sid)
  expect_length(.SessionLogStore$new(cwd = proj)$list(part()), 0L)
})

test_that("put() leaves another user's log alone", {
  proj <- local_store_env()
  sid <- save_fixture(proj, list(Turn("user", "q"), Turn("assistant", "r")))
  set_owner(proj, sid, "bob")
  path <- .find_session_path(sid, proj)
  before <- readLines(path)
  bound_store(proj)$put(part(), new_record(sid, title = "x", title_source = "user"))
  expect_identical(readLines(path), before)
})

test_that("delete() removes only this project's, this user's session", {
  proj <- local_store_env()
  other <- withr::local_tempdir()
  mine <- save_fixture(proj, list(Turn("user", "q"), Turn("assistant", "r")))
  bobs <- save_fixture(proj, list(Turn("user", "q"), Turn("assistant", "r")))
  set_owner(proj, bobs, "bob")
  theirs <- save_fixture(other, list(Turn("user", "q"), Turn("assistant", "r")))
  st <- bound_store(proj)
  for (id in list(bobs, theirs, "../x", "c_zz", NA_character_, 1L))
    st$delete(part(), id)
  expect_false(is.null(.find_session_path(bobs, proj)))
  expect_false(is.null(.find_session_path(theirs, other)))
  st$delete(part(), mine)
  expect_null(.find_session_path(mine, proj))
  expect_length(st$list(part()), 0L)
})

test_that("delete() by shinychat record id and of a pending conversation", {
  proj <- local_store_env()
  sid <- save_fixture(proj, list(Turn("user", "q"), Turn("assistant", "r")))
  st <- bound_store(proj)
  rec <- new_record(sid)
  st$put(part(), rec)
  st$delete(part(), rec$id)
  expect_null(.find_session_path(sid, proj))

  rec2 <- new_record(.generate_uuid_v4(), id = "c_00001a2b3c4d5e6f7a8ff")
  st$put(part(), rec2)
  st$delete(part(), rec2$id)
  expect_length(st$list(part()), 0L)
})
