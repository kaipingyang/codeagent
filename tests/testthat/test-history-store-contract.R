# tests/testthat/test-history-store-contract.R
# The session-log store against the shinychat it is pinned to. These tests use
# shinychat internals on purpose: they fail loudly when a shinychat update
# changes the record shape, the replay path or eviction, so the store can be
# adjusted before a user's history is affected. Run first when bumping the
# shinychat SHA.

library(ellmer)

contract_record <- function() {
  home <- withr::local_tempdir(.local_envir = parent.frame())
  proj <- withr::local_tempdir(.local_envir = parent.frame())
  withr::local_envvar(CODEAGENT_HOME = home, .local_envir = parent.frame())
  req <- ContentToolRequest(id = "t1", name = "Read", arguments = list(path = "x.R"))
  turns <- list(
    Turn("user", "read x.R"),
    Turn("assistant", list(req)),
    Turn("user", list(ContentToolResult(value = "x <- 1", request = req))),
    Turn("assistant", "It assigns 1."),
    Turn("user", "thanks"),
    Turn("assistant", "Welcome."))
  ch <- chat_anthropic(model = "claude-sonnet-4-6")
  ch$set_turns(turns)
  sid <- save_session(ch, cwd = proj)
  st <- .SessionLogStore$new(cwd = proj)$bind(chat_anthropic(model = "claude-sonnet-4-6"), list())
  part <- shinychat:::conversation_partition("chat", .history_local_user())
  list(rec = st$get(part, sid), turns = turns, store = st, part = part, sid = sid)
}

test_that("records pass shinychat's schema check and path walk", {
  x <- contract_record()
  expect_identical(shinychat:::check_schema_version(x$rec$schema_version), 1L)
  expect_identical(shinychat:::record_path_node_ids(x$rec), names(x$rec$nodes))
  expect_identical(shinychat:::record_turn_count(x$rec), length(x$turns))
})

test_that("shinychat groups the turns into the same nodes", {
  x <- contract_record()
  groups <- shinychat:::group_ellmer_turns(x$turns)
  expect_identical(lengths(groups), unname(lengths(lapply(x$rec$nodes, `[[`, "turns"))))
})

test_that("shinychat derives the UI for nodes stored without one", {
  x <- contract_record()
  for (node in x$rec$nodes) {
    ui <- shinychat:::derive_node_ui_from_turns(node, tools = list())
    expect_true(length(ui) >= 1L)
    expect_true(shinychat:::is_stored_ui_versioned(ui))
  }
})

test_that("the next reply extends the reopened record after its last node", {
  x <- contract_record()
  recorded <- c(lapply(x$turns, contents_record),
                list(contents_record(Turn("user", "more")),
                     contents_record(Turn("assistant", "sure"))))
  ext <- shinychat:::extend_record_linear(x$rec, recorded, tools = list())
  expect_identical(shinychat:::record_turn_count(ext), length(recorded))
  expect_identical(ext$nodes[[ext$current_leaf]]$parent, "n_0005")
  expect_identical(ext$nodes$n_0004$children, list("n_0005"))
})

test_that("shinychat never evicts with max_store_mb = NULL, and does with a limit", {
  spy <- R6::R6Class("spy", inherit = shinychat::ConversationStore, public = list(
    deleted = character(0),
    list = function(partition) list(
      list(id = "c_1", title = "a", created_at = "2026-01-02T00:00:00Z",
           updated_at = "2026-01-02T00:00:00Z", size_bytes = 500 * 1024^2),
      list(id = "c_2", title = "b", created_at = "2026-01-01T00:00:00Z",
           updated_at = "2026-01-01T00:00:00Z", size_bytes = 500 * 1024^2)),
    get = function(partition, id) NULL,
    put = function(partition, record) invisible(NULL),
    delete = function(partition, id) { self$deleted <- c(self$deleted, id); invisible(NULL) }))
  evict <- function(max_store_mb) {
    store <- spy$new()
    opts <- shinychat::history_options(store = store, scope = function(s) "u",
                                       max_store_mb = max_store_mb)
    ctl <- shinychat:::HistoryController$new("chat", chat_anthropic(model = "claude-sonnet-4-6"),
                                             opts, shiny::MockShinySession$new())
    ctl$partition <- shinychat:::conversation_partition("chat", "u")
    ctl$.__enclos_env__$private$evict_if_needed()
    store$deleted
  }
  expect_length(evict(NULL), 0L)
  expect_identical(codeagent_history_options(tempdir())$max_store_mb, NULL)
  expect_true(length(suppressWarnings(evict(100))) > 0L)
})
