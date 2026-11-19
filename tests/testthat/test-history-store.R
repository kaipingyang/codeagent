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

test_that("ids that are not this project's sessions resolve to nothing", {
  proj <- local_store_env()
  other <- withr::local_tempdir()
  theirs <- save_fixture(other, list(Turn("user", "q"), Turn("assistant", "r")))
  st <- bound_store(proj)
  for (id in list(theirs, "../x", "c_zz", "c_0123456789abc", NA_character_, 1L, c("a", "b")))
    expect_null(st$get(part(), id))
})

test_that("put() and delete() do not touch the log yet", {
  proj <- local_store_env()
  sid <- save_fixture(proj, list(Turn("user", "q"), Turn("assistant", "r")))
  path <- .find_session_path(sid, proj)
  before <- readLines(path)
  st <- bound_store(proj)
  st$put(part(), st$get(part(), sid))
  st$delete(part(), sid)
  expect_identical(readLines(path), before)
})
