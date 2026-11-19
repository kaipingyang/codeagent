# tests/testthat/test-workspace.R
# Workspace kinds, options, UI and the per-session server.

test_that("kinds and options are validated", {
  k <- codeagent_workspace_kind("tfl", function(id, session) id)
  expect_s3_class(k, "codeagent_workspace_kind")
  expect_error(codeagent_workspace_kind("bad name", identity), "kind")
  expect_error(codeagent_workspace_kind("x", "nope"), "render")
  expect_error(codeagent_workspace_kind("x", identity, title = "t"), "title")
  o <- workspace_options(k, max_tabs = 5)
  expect_identical(names(o$kinds), "tfl")
  expect_identical(o$max_tabs, 5L)
  expect_error(workspace_options(list("x")), "kinds")
  expect_error(workspace_options(max_tabs = 0), "max_tabs")
})

test_that("the UI holds the strip output and the body", {
  html <- as.character(codeagent_workspace_ui("ws1"))
  expect_match(html, 'data-ca-ws="ws1"', fixed = TRUE)
  expect_match(html, 'id="ws1_strip"', fixed = TRUE)
  expect_match(html, 'id="ws1_body"', fixed = TRUE)
  expect_match(as.character(htmltools::renderTags(head_assets())$head), "codeagent-www/workspace.js", fixed = TRUE)
})

ws_server <- function(options, chat = NULL, cwd = tempdir()) {
  function(input, output, session) {
    state <- shiny::reactiveValues(ws_layout = NULL, ws_epoch = 0L)
    session$userData$state <- state
    session$userData$ws <- .workspace_server(input, output, session, state, options,
                                             chat = chat, cwd = cwd)
  }
}

test_that("open, dedupe, close and events drive the layout", {
  opts <- workspace_options(list(
    codeagent_workspace_kind("note", function(id, session) htmltools::p(paste("note", id)),
                             title = function(id) paste("Note", id)),
    codeagent_workspace_kind("config", function(id, session) "cfg", pinned = TRUE)),
    builtin = FALSE)
  shiny::testServer(ws_server(opts), {
    ws <- session$userData$ws
    session$flushReact()
    expect_identical(vapply(ws$tabs(), `[[`, "", "kind"), "config")   # pinned at start
    a <- ws$open("note", "a")
    b <- ws$open("note", "b")
    expect_identical(ws$open("note", "a"), a)                        # dedupe
    session$flushReact()
    expect_length(ws$tabs(), 3L)
    expect_identical(ws$active()$id, a)
    expect_identical(ws$tabs()[[2]]$title, "Note a")
    expect_match(as.character(output[[paste0("ca_ws_out_", a)]]$html), "note a", fixed = TRUE)
    expect_match(as.character(output$ca_ws_strip$html), "Note b", fixed = TRUE)

    session$setInputs(ca_ws_event = list(action = "close", tab = a, nonce = 1))
    expect_identical(vapply(ws$tabs(), `[[`, "", "content_id"), c("config", "b"))
    session$setInputs(ca_ws_event = list(action = "pin", tab = b, nonce = 2))
    expect_true(ws$tabs()[[2]]$pinned)
    session$setInputs(ca_ws_event = list(action = "bogus", tab = b, nonce = 3))
    expect_length(ws$tabs(), 2L)
    expect_error(ws$open("note", NA_character_), "content_id")
  })
})

test_that("a tab of an unknown kind shows a note, and restore re-mounts", {
  opts <- workspace_options(builtin = FALSE)
  shiny::testServer(ws_server(opts), {
    ws <- session$userData$ws
    t <- ws$open("gone", "x")
    session$flushReact()
    expect_match(as.character(output[[paste0("ca_ws_out_", t)]]$html), "Cannot show", fixed = TRUE)
    saved <- ws$layout()
    ws$restore(NULL)
    session$flushReact()
    expect_length(ws$tabs(), 0L)
    ws$restore(saved)
    session$flushReact()
    expect_identical(ws$tabs()[[1]]$content_id, "x")
    expect_match(as.character(output[[paste0("ca_ws_out_", t)]]$html), "Cannot show", fixed = TRUE)
  })
})

test_that("built-in kinds: a tool result by request id, a project file by path", {
  ch <- ellmer::chat_anthropic(model = "claude-sonnet-4-6")
  req <- ellmer::ContentToolRequest(id = "req_1", name = "Read", arguments = list(path = "a.R"))
  res <- ellmer::ContentToolResult(value = "x <- 1", request = req,
                                   extra = list(display = list(title = "Read a.R", html = "<p>x</p>"),
                                                codeagent = list(result_id = "res_1")))
  ch$set_turns(list(ellmer::Turn("user", "go"), ellmer::Turn("assistant", list(req)),
                    ellmer::Turn("user", list(res))))
  cwd <- withr::local_tempdir()
  writeLines("y <- 2", file.path(cwd, "b.R"))
  shiny::testServer(ws_server(workspace_options(), chat = ch, cwd = cwd), {
    ws <- session$userData$ws
    r <- ws$open("result", "res_1")
    f <- ws$open("file", "b.R")
    bad <- ws$open("file", "../../etc/passwd")
    gone <- ws$open("result", "req_missing")
    session$flushReact()
    expect_match(as.character(output[[paste0("ca_ws_out_", r)]]$html), "toolcard", fixed = TRUE)
    expect_match(as.character(output[[paste0("ca_ws_out_", f)]]$html), "y &lt;- 2|y <- 2")
    expect_match(as.character(output[[paste0("ca_ws_out_", bad)]]$html), "cannot be shown", fixed = TRUE)
    expect_match(as.character(output[[paste0("ca_ws_out_", gone)]]$html), "no longer", fixed = TRUE)
    expect_identical(ws$tabs()[[2]]$title, "b.R")
  })
})

test_that("the layout is saved to the session log on change and read back", {
  cwd <- withr::local_tempdir()
  ch <- ellmer::chat_anthropic(model = "claude-sonnet-4-6")
  ch$set_turns(list(ellmer::Turn("user", "q"), ellmer::Turn("assistant", "r")))
  l <- .ws_open(.ws_open(.ws_layout(), "result", "res_1", "Read a.R"), "file", "b.R")
  sid <- save_session(ch, cwd, workspace_state = l)
  expect_identical(.ws_read(sid, cwd)$tabs, .ws_validate(l)$tabs)
  path <- .find_session_path(sid, cwd)
  n <- length(readLines(path))
  save_session(ch, cwd, sid, workspace_state = l)          # unchanged: no new line
  expect_false(.ws_save(sid, cwd, l))
  expect_length(readLines(path), n)
  l2 <- .ws_close(l, "t_2")
  expect_true(.ws_save(sid, cwd, l2))
  expect_identical(length(.ws_read(sid, cwd)$tabs), 1L)
  expect_false(.ws_save(.generate_uuid_v4(), cwd, l2))      # no log yet: nothing
  expect_false(.ws_save("../x", cwd, l2))
  # a log from before workspaces: no layout
  ch2 <- ellmer::chat_anthropic(model = "claude-sonnet-4-6")
  ch2$set_turns(list(ellmer::Turn("user", "q")))
  expect_null(.ws_read(save_session(ch2, cwd), cwd))
})

test_that("switching conversations swaps the layout, and changes are saved", {
  cwd <- withr::local_tempdir()
  ch <- ellmer::chat_anthropic(model = "claude-sonnet-4-6")
  ch$set_turns(list(ellmer::Turn("user", "q"), ellmer::Turn("assistant", "r")))
  saved <- .ws_open(.ws_layout(), "note", "kept")
  sid_a <- save_session(ch, cwd, workspace_state = saved)
  sid_b <- save_session(ch, cwd)
  opts <- workspace_options(list(codeagent_workspace_kind("note", function(id, s) id)),
                            builtin = FALSE)
  shiny::testServer(function(input, output, session) {
    state <- shiny::reactiveValues(ws_layout = NULL, ws_epoch = 0L, session_id = sid_b)
    session$userData$state <- state
    session$userData$ws <- .workspace_server(input, output, session, state, opts, cwd = cwd)
  }, {
    ws <- session$userData$ws; state <- session$userData$state
    session$flushReact()
    ws$open("note", "fresh")
    session$flushReact()
    expect_identical(.ws_read(sid_b, cwd)$tabs[[1]]$content_id, "fresh")
    state$session_id <- sid_a
    session$flushReact()
    expect_identical(vapply(ws$tabs(), `[[`, "", "content_id"), "kept")
    state$session_id <- .generate_uuid_v4()                 # a new conversation
    session$flushReact()
    expect_length(ws$tabs(), 0L)
  })
})

test_that("tool requests left without a result are closed with an error result", {
  ch <- ellmer::chat_anthropic(model = "claude-sonnet-4-6")
  r1 <- ellmer::ContentToolRequest(id = "a", name = "Read", arguments = list())
  r2 <- ellmer::ContentToolRequest(id = "b", name = "Bash", arguments = list())
  r3 <- ellmer::ContentToolRequest(id = "c", name = "Read", arguments = list())
  done <- ellmer::ContentToolResult(value = "ok", request = r1)
  ch$set_turns(list(
    ellmer::Turn("user", "go"),
    ellmer::Turn("assistant", list(r1, r2)),
    ellmer::Turn("user", list(done)),
    ellmer::Turn("assistant", "then"),
    ellmer::Turn("assistant", list(r3))))
  expect_identical(.close_dangling_tool_requests(ch), 2L)
  turns <- ch$get_turns()
  expect_length(turns, 6L)
  third <- turns[[3]]@contents
  expect_length(third, 2L)                                  # joined its round
  expect_identical(third[[2]]@request@id, "b")
  expect_match(third[[2]]@error, "Interrupted")
  expect_identical(turns[[6]]@contents[[1]]@request@id, "c")
  expect_identical(.close_dangling_tool_requests(ch), 0L)   # nothing left
})
