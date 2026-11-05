# Embedding codeagent in a host Shiny app (R/embed.R).

.embed_client <- function(...) {
  chat <- ellmer::chat_openai_compatible(
    base_url = "http://127.0.0.1:1", model = "m", credentials = function() "k")
  codeagent_client(chat, register_tools = FALSE, cwd = withr::local_tempdir(.local_envir = parent.frame(2)), ...)
}

test_that("codeagent_chat_ui is the chat the server modules address", {
  html <- as.character(codeagent_chat_ui(greeting = "Hello host", placeholder = "Ask"))
  expect_match(html, 'id="chat"')
  expect_match(html, "ca_interaction_ui")
  expect_match(html, "Hello host")
  expect_match(html, "Ask")
  expect_match(as.character(codeagent_chat_ui(id = "other")), 'id="chat"')  # id is fixed
})

test_that("codeagent_canvas_ui holds the canvas container and refresh button", {
  html <- as.character(codeagent_canvas_ui())
  expect_match(html, .GENUI_CANVAS_ID, fixed = TRUE)
  expect_match(html, "ca_genui_refresh")
  expect_error(codeagent_canvas_ui(list()), "canvas_options")
})

test_that("codeagent_head_assets returns codeagent's head tags", {
  html <- htmltools::renderTags(codeagent_head_assets())$head
  expect_match(html, "codeagent-www/agent.js", fixed = TRUE)
})

test_that("host tools need a declared capability", {
  t <- ellmer::tool(function() "x", name = "HostPing", description = "d", arguments = list())
  expect_error(.check_host_tools(list(t), list()), "HostPing")
  expect_error(.check_host_tools(list("nope"), list()), "ellmer::tool")
  expect_true(.check_host_tools(list(t), list(HostPing = "read")))
})

test_that("codeagent_server registers selected built-ins and host tools after the first flush", {
  host <- ellmer::tool(function() ellmer::ContentToolResult(value = list(a = 1, b = "x")),
                       name = "HostInfo", description = "d", arguments = list())
  client <- .embed_client(tools = c("Read", "AskUserQuestion", "AskUserForm"), permission_mode = "plan")
  shiny::testServer(function(input, output, session) {
    session$userData$srv <- codeagent_server(input, output, session, client,
                                             tools = list(host), tool_meta = list(HostInfo = "read"))
  }, {
    srv <- session$userData$srv
    expect_true(shiny::isolate(srv$state$initializing))
    session$flushReact()
    expect_false(shiny::isolate(srv$state$initializing))
    tools <- names(client$chat$get_tools())
    expect_setequal(tools, c("Read", "AskUserQuestion", "AskUserForm", "HostInfo"))
    expect_s3_class(srv$stream_task, "ExtendedTask")
    expect_true(is.function(srv$settings$shiny_ask_form_fn))
    out <- S7::S7_data(client$chat$get_tools()$HostInfo)()
    expect_type(out@value, "character")      # normalized for the provider
  })
})

test_that("codeagent_server validates its inputs", {
  client <- .embed_client()
  expect_error(codeagent_server(NULL, NULL, NULL, list()), "CodeagentClient")
  expect_error(codeagent_server(NULL, NULL, NULL, client, canvas = list()), "canvas_options")
})

test_that("setting_sources = \"project\" keeps user-level files out of the prompt", {
  home <- withr::local_tempdir()
  dir.create(file.path(home, ".claude"))
  writeLines("PERSONAL_MARKER", file.path(home, ".claude", "CLAUDE.md"))
  cwd <- withr::local_tempdir()
  writeLines("HOST_MARKER", file.path(cwd, "CLAUDE.md"))
  withr::local_envvar(HOME = home)
  expect_match(load_settings(cwd)$claude_md, "PERSONAL_MARKER")
  s <- load_settings(cwd, setting_sources = "project")
  expect_false(grepl("PERSONAL_MARKER", s$claude_md))
  expect_match(s$claude_md, "HOST_MARKER")
  chat <- ellmer::chat_openai_compatible(base_url = "http://127.0.0.1:1", model = "m", credentials = function() "k")
  client <- codeagent_client(chat, cwd = cwd, register_tools = FALSE, setting_sources = "project")
  expect_false(grepl("PERSONAL_MARKER", client$chat$get_system_prompt()))
  expect_error(codeagent_client(chat, cwd = cwd, register_tools = FALSE, setting_sources = "local"), "setting_sources")
  expect_null(load_settings(cwd, setting_sources = character(0))$claude_md)
  # a user settings.json is skipped too
  withr::local_envvar(CODEAGENT_HOME = file.path(home, "cahome"))
  dir.create(file.path(home, "cahome"))
  writeLines('{"max_turns": 7}', file.path(home, "cahome", "settings.json"))
  expect_equal(load_settings(cwd)$max_turns, 7)
  expect_false(identical(load_settings(cwd, setting_sources = "project")$max_turns, 7))
})

test_that("a canvas with a tools= selection that leaves out genui warns", {
  expect_true(.tool_spec_allows_genui(NULL))
  client <- .embed_client(tools = c("Read"))
  expect_false(.tool_spec_allows_genui(client$settings$tools_spec))
  client2 <- .embed_client(tools = c("Read", "genui"))
  expect_true(.tool_spec_allows_genui(client2$settings$tools_spec))
  expect_warning(
    shiny::testServer(function(input, output, session) {
      codeagent_server(input, output, session, client, canvas = canvas_options())
    }, {}),
    "genui")
})

test_that("tool_meta values and host tool names are validated up front", {
  t <- ellmer::tool(function() "x", name = "HostPing", description = "d", arguments = list())
  expect_error(.check_host_tools(list(t), list(HostPing = "readonly")), "invalid for: HostPing")
  expect_error(.check_host_tools(list(t), list(HostPing = c("read", "write"))), "invalid")
  clash <- ellmer::tool(function() "x", name = "Read", description = "d", arguments = list())
  expect_error(.check_host_tools(list(clash), list(Read = "read")), "clash")
})

test_that("host tools go through the normal setup: disallowed_tools can remove them", {
  host <- ellmer::tool(function() "x", name = "HostDrop", description = "d", arguments = list())
  client <- .embed_client(tools = c("Read"), disallowed_tools = "HostDrop")
  shiny::testServer(function(input, output, session) {
    codeagent_server(input, output, session, client,
                     tools = list(host), tool_meta = list(HostDrop = "read"))
  }, {
    session$flushReact()
    expect_false("HostDrop" %in% names(client$chat$get_tools()))
    expect_true("Read" %in% names(client$chat$get_tools()))
  })
})

test_that("a tool-setup failure fails closed", {
  client <- .embed_client(tools = c("Read"))
  testthat::local_mocked_bindings(.register_all_tools = function(...) stop("boom"))
  shiny::testServer(function(input, output, session) {
    session$userData$srv <- codeagent_server(input, output, session, client)
  }, {
    session$flushReact()
    expect_length(client$chat$get_tools(), 0)
    expect_true(shiny::isolate(session$userData$srv$state$initializing))
    expect_match(shiny::isolate(session$userData$srv$state$init_step), "boom")
  })
})

test_that("a client serving an open session cannot be bound to a second one", {
  client <- .embed_client()
  attr(client$chat, "codeagent_server_session") <- list(isClosed = function() FALSE)
  expect_error(
    shiny::testServer(function(input, output, session) {
      codeagent_server(input, output, session, client)
    }, {}),
    "already serving another open Shiny session")
  attr(client$chat, "codeagent_server_session") <- list(isClosed = function() TRUE)
  expect_no_error(shiny::testServer(function(input, output, session) {
    codeagent_server(input, output, session, client)
  }, {}))
})

test_that("codeagent_sessions_ui holds the session list and its buttons", {
  html <- as.character(codeagent_sessions_ui())
  expect_match(html, "session_list_ui")
  expect_match(html, "new_session")
  expect_match(html, "delete_session_btn")
  expect_match(html, "History")
  expect_false(grepl("<h6", as.character(codeagent_sessions_ui(title = NULL))))
})

test_that("codeagent_server(sessions = TRUE) lists, restores and starts conversations", {
  home <- withr::local_tempdir(); withr::local_envvar(CODEAGENT_HOME = home)
  client <- .embed_client(permission_mode = "plan")
  cwd <- client$settings$cwd
  # an earlier conversation of this workspace
  old <- ellmer::chat_openai_compatible(base_url = "http://127.0.0.1:1", model = "m", credentials = function() "k")
  old$set_turns(list(ellmer::Turn("user", "earlier question"), ellmer::Turn("assistant", "earlier answer")))
  sid <- save_session(old, cwd = cwd)
  expect_error(shiny::testServer(function(input, output, session)
    codeagent_server(input, output, session, client, sessions = NA), {}), "sessions")
  shiny::testServer(function(input, output, session) {
    session$userData$srv <- codeagent_server(input, output, session, client, sessions = TRUE)
  }, {
    srv <- session$userData$srv
    session$flushReact()
    expect_match(output$session_list_ui$html, "earlier question")
    expect_match(output$session_list_ui$html, sid, fixed = TRUE)
    expect_length(client$chat$get_turns(), 0L)               # a page opens on a new conversation
    session$setInputs(ca_load_session = sid)
    expect_length(client$chat$get_turns(), 2L)
    expect_identical(shiny::isolate(srv$state$session_id), sid)
    session$setInputs(new_session = 1)
    expect_length(client$chat$get_turns(), 0L)
    expect_false(identical(shiny::isolate(srv$state$session_id), sid))
    session$setInputs(ca_load_session = "../../etc/passwd")  # not a session id
    expect_length(client$chat$get_turns(), 0L)
  })
})

test_that("codeagent_server without sessions serves no session list", {
  client <- .embed_client()
  shiny::testServer(function(input, output, session) codeagent_server(input, output, session, client), {
    session$flushReact()
    expect_error(output$session_list_ui)
  })
})

test_that("a host tool's own card survives save and restore (replay keeps extra$display)", {
  home <- withr::local_tempdir(); withr::local_envvar(CODEAGENT_HOME = home)
  cwd <- withr::local_tempdir()
  ch <- ellmer::chat_openai_compatible(base_url = "http://127.0.0.1:1", model = "m", credentials = function() "k")
  req <- ellmer::ContentToolRequest(id = "c1", name = "HostTFL", arguments = list(key = "t_dm"))
  res <- ellmer::ContentToolResult(value = "{\"key\":\"t_dm\"}", request = req,
    extra = list(display = list(title = "t_dm: Demographics",
                                html = htmltools::div(htmltools::tags$iframe(src = "out/t_dm.html")))))
  ch$set_turns(list(ellmer::Turn("user", "go"), ellmer::Turn("assistant", list(req)),
                    ellmer::Turn("user", list(res)), ellmer::Turn("assistant", "done")))
  sid <- save_session(ch, cwd = cwd)
  ch2 <- ellmer::chat_openai_compatible(base_url = "http://127.0.0.1:1", model = "m", credentials = function() "k")
  restore_session_into_chat(ch2, session_id = sid, cwd = cwd)
  restored <- ch2$get_turns()[[3]]@contents[[1]]
  adapted <- .adapt_tool_result(restored)
  html <- paste(as.character(adapted@extra$display$html), collapse = "")
  expect_match(html, "out/t_dm.html", fixed = TRUE)
  expect_match(as.character(adapted@extra$display$title), "t_dm: Demographics")
  # a result without a host card still gets codeagent's own presentation
  plain <- .adapt_tool_result(ellmer::ContentToolResult(value = "hello", request = req))
  expect_false(grepl("iframe", paste(as.character(plain@extra$display$html), collapse = "")))
})
