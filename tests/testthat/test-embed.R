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

# shinychat history backend ----------------------------------------------------

.hist_round <- function(chat, raw_reply, gated_reply, session) {
  # one finished round as the stream leaves it: user (with injected context),
  # a tool call, the model's raw reply; then the gated text closes the stream
  round_start <- length(chat$get_turns())
  req <- ellmer::ContentToolRequest(id = paste0("c", round_start), name = "HostT", arguments = list(k = "v"))
  res <- ellmer::ContentToolResult(value = "{}", request = req,
                                   extra = list(display = list(title = "Card", html = htmltools::div("card"))))
  chat$set_turns(c(chat$get_turns(), list(
    ellmer::Turn("user", "Generate t_dm\n<system-reminder>internal context</system-reminder>"),
    ellmer::Turn("assistant", list(req)), ellmer::Turn("user", list(res)),
    ellmer::Turn("assistant", raw_reply))))
  .append_presentation(list(), chat, round_start, gated_reply)
  p <- shinychat::chat_append("chat", gated_reply, session = session)
  for (i in 1:30) later::run_now(0.02)
  invisible(p)
}

test_that("codeagent_server validates history", {
  client <- .embed_client()
  expect_error(shiny::testServer(function(input, output, session)
    codeagent_server(input, output, session, client, history = "yes"), {}), "history")
  expect_match(as.character(codeagent_chat_ui()), "show-history=\"false\"", fixed = TRUE)
  expect_false(grepl("show-history", as.character(codeagent_chat_ui(history = TRUE)), fixed = TRUE))
})

test_that("shinychat history records what the user saw and restores the model context from the session log", {
  home <- withr::local_tempdir(); withr::local_envvar(CODEAGENT_HOME = home)
  store_dir <- withr::local_tempdir()
  client <- .embed_client(permission_mode = "plan")
  chat <- client$chat
  cwd <- client$settings$cwd
  opts <- shinychat::history_options(restore_mode = "none", title = NULL, scope = "u1",
                                     store = shinychat::FileConversationStore$new(dir = store_dir))
  shiny::testServer(function(input, output, session) {
    session$userData$srv <- codeagent_server(input, output, session, client, history = opts,
                                             greeting = "Hi")
  }, {
    srv <- session$userData$srv
    session$flushReact()
    expect_false(is.null(attr(chat, "codeagent_presentation_chat")))
    sid_a <- shiny::isolate(srv$state$session_id)
    .hist_round(chat, "Raw reply naming BGB-001-0007", "Gated reply [redacted]", session)
    save_session(chat, cwd, sid_a)                                  # the end-of-round save
    session$flushReact()

    store <- shinychat::FileConversationStore$new(dir = store_dir)
    files <- list.files(store_dir, recursive = TRUE, full.names = TRUE)
    txt <- paste(unlist(lapply(files, readLines, warn = FALSE)), collapse = "\n")
    expect_true(grepl("Gated reply [redacted]", txt, fixed = TRUE))
    expect_false(grepl("BGB-001-0007", txt, fixed = TRUE))          # output gate before the record
    expect_false(grepl("internal context", txt, fixed = TRUE))      # no injected context
    expect_true(grepl("Card", txt, fixed = TRUE))                   # the host's card
    expect_true(grepl(sid_a, txt, fixed = TRUE))                    # codeagent session id saved

    # a new conversation empties the model context and starts a new session
    session$setInputs(chat_history_new = 1)
    expect_length(chat$get_turns(), 0L)
    expect_false(identical(shiny::isolate(srv$state$session_id), sid_a))

    # opening the first one again: model context from the session log (raw,
    # as the model had it), session id back
    conv <- unique(basename(dirname(list.files(store_dir, pattern = "^record\\.json$", recursive = TRUE))))
    expect_length(conv, 1L)
    session$setInputs(chat_history_select = list(id = conv[[1]]))
    expect_identical(shiny::isolate(srv$state$session_id), sid_a)
    expect_true(any(grepl("BGB-001-0007", vapply(chat$get_turns(), function(t) t@text, ""), fixed = TRUE)))
  })
})

test_that("presentation turns: reminders stripped, gated text, tool cards kept", {
  req <- ellmer::ContentToolRequest(id = "c1", name = "HostT", arguments = list(k = "v"))
  turns <- list(ellmer::Turn("user", "go <system-reminder>secret</system-reminder>"),
                ellmer::Turn("assistant", list(ellmer::ContentText("thinking aloud"), req)),
                ellmer::Turn("assistant", "raw final"))
  out <- .presentation_turns(turns, list(), NULL, shown_text = "shown final")
  expect_identical(out[[1]]@text, "go")
  expect_s3_class(out[[2]]@contents[[2]], "ellmer::ContentToolRequest")
  expect_identical(out[[3]]@text, "shown final")
})

# Always allow / mode switch / on_restore ---------------------------------------

test_that("'Always allow this tool' approves now, the queued same-tool requests, and later ones", {
  client <- .embed_client(permission_mode = "default")
  shiny::testServer(function(input, output, session) {
    session$userData$srv <- codeagent_server(input, output, session, client)
  }, {
    srv <- session$userData$srv
    session$flushReact()
    ask <- srv$settings$shiny_ask_fn
    got <- list()
    keep <- function(tag) function(v) got[[tag]] <<- v
    promises::then(ask("HostWrite", list(a = 1)), keep("first"))
    promises::then(ask("HostWrite", list(a = 2)), keep("queued"))
    promises::then(ask("OtherTool", list()), keep("other"))
    session$flushReact()
    expect_match(paste(output$ca_interaction_ui$html, collapse = ""), "ca_tool_allow_always")
    session$setInputs(ca_tool_allow_always = 1)
    for (i in 1:10) later::run_now(0.01)
    expect_true(isTRUE(got$first)); expect_true(isTRUE(got$queued))
    expect_null(got$other)                                   # another tool still asks
    expect_identical(shiny::isolate(srv$state$pending_interaction$payload$tool_name), "OtherTool")
    promises::then(ask("HostWrite", list(a = 3)), keep("later"))
    for (i in 1:10) later::run_now(0.01)
    expect_true(isTRUE(got$later))                           # no bar for it any more
  })
})

test_that("codeagent_mode_ui + codeagent_server(modes =) switch the session's permission mode", {
  modes <- c("Ask before changes" = "default", "Run without asking" = "bypass")
  html <- as.character(codeagent_mode_ui(modes))
  expect_match(html, "ca_perm_mode"); expect_match(html, "Run without asking")
  expect_error(codeagent_mode_ui(c(x = "plan")), "modes")
  client <- .embed_client(permission_mode = "default")
  shiny::testServer(function(input, output, session) codeagent_server(input, output, session, client, modes = modes), {
    session$flushReact()
    ctx <- .gate_ctx_for(client$chat)
    expect_identical(ctx$mode_env$mode, "default")
    session$setInputs(ca_perm_mode = "bypass")
    expect_identical(ctx$mode_env$mode, "bypass")
    session$setInputs(ca_perm_mode = "plan")                 # not offered: ignored
    expect_identical(ctx$mode_env$mode, "bypass")
    session$setInputs(ca_perm_mode = "default")
    expect_identical(ctx$mode_env$mode, "default")
  })
  expect_error(shiny::testServer(function(input, output, session)
    codeagent_server(input, output, session, .embed_client(), on_restore = "x"), {}), "on_restore")
})

test_that("on_restore runs after a conversation is opened from codeagent's list", {
  home <- withr::local_tempdir(); withr::local_envvar(CODEAGENT_HOME = home)
  client <- .embed_client(permission_mode = "plan")
  old <- ellmer::chat_openai_compatible(base_url = "http://127.0.0.1:1", model = "m", credentials = function() "k")
  old$set_turns(list(ellmer::Turn("user", "q"), ellmer::Turn("assistant", "a")))
  sid <- save_session(old, cwd = client$settings$cwd)
  seen <- NULL
  shiny::testServer(function(input, output, session)
    codeagent_server(input, output, session, client, history = "codeagent",
                     on_restore = function(chat) seen <<- length(chat$get_turns())), {
    session$flushReact()
    session$setInputs(ca_load_session = sid)
    expect_identical(seen, 2L)
  })
})
