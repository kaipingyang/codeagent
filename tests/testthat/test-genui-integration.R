# GenUI wiring into the client: activation, registration, prompt, reminder,
# result routing and session persistence (references/plan/42-genui-phase1-3.md).

# -- activation -----------------------------------------------------------------

test_that("GenUI is on by default only for per-session apps", {
  local_mocked_bindings(.genui_available = function() TRUE)
  expect_true(.genui_wanted(list(tools_spec = NULL), per_session = TRUE))
  expect_false(.genui_wanted(list(tools_spec = NULL), per_session = FALSE))
})

test_that("naming genui enables it even for a shared client", {
  local_mocked_bindings(.genui_available = function() TRUE)
  spec <- .resolve_tool_spec(c("files", "genui"))
  expect_true(.genui_wanted(list(tools_spec = spec), per_session = FALSE))
})

test_that("a selection that omits genui keeps it off", {
  local_mocked_bindings(.genui_available = function() TRUE)
  spec <- .resolve_tool_spec(c("files", "shell"))
  expect_false(.genui_wanted(list(tools_spec = spec), per_session = TRUE))
})

test_that("disallowed_tools = 'genui' always wins", {
  local_mocked_bindings(.genui_available = function() TRUE)
  dis <- .resolve_disallowed_tools("genui")
  expect_false(.genui_wanted(list(tools_spec = NULL, disallowed_tools = dis),
                             per_session = TRUE))
  spec <- .resolve_tool_spec("genui")
  expect_false(.genui_wanted(list(tools_spec = spec, disallowed_tools = dis),
                             per_session = TRUE))
})

test_that("the default quietly stays off when shinygenui is unavailable", {
  local_mocked_bindings(.genui_available = function() FALSE)
  expect_false(.genui_wanted(list(tools_spec = NULL), per_session = TRUE))
})

test_that("an explicit request for unavailable GenUI warns", {
  local_mocked_bindings(.genui_available = function() FALSE)
  spec <- .resolve_tool_spec("genui")
  expect_warning(
    expect_false(.genui_wanted(list(tools_spec = spec), per_session = TRUE)),
    "shinygenui")
})

test_that("an explicit genui request is not reported as unfulfilled", {
  # The client cannot register canvas tools itself -- only codeagent_app() can
  # -- so the CLI-side report must not call the request a failure.
  chat <- ellmer::chat_openai(model = "gpt-4.1", credentials = function() "test")
  spec <- .resolve_tool_spec(c("genui"))
  expect_no_warning(.report_unfulfilled_tools(chat, spec))
})

# -- registration ---------------------------------------------------------------

test_that(".register_genui_tools registers every canvas tool from the adapter", {
  skip_if_no_genui()
  chat <- ellmer::chat_openai(model = "gpt-4.1", credentials = function() "test")
  a <- GenUIAdapter$new(data_env = genui_test_env())
  .register_genui_tools(chat, list(genui = a))
  names <- vapply(chat$get_tools(), function(t) t@name, "")
  expect_setequal(names, .genui_tool_names())
})

test_that(".register_genui_tools is a no-op without an adapter", {
  chat <- ellmer::chat_openai(model = "gpt-4.1", credentials = function() "test")
  .register_genui_tools(chat, list())
  expect_length(chat$get_tools(), 0L)
})

test_that("a full registration keeps canvas tools when genui is selected", {
  skip_if_no_genui()
  chat <- ellmer::chat_openai(model = "gpt-4.1", credentials = function() "test")
  settings <- list(permission_mode = "bypass", cwd = tempdir(),
                   tools_spec = .resolve_tool_spec(c("Read", "genui")),
                   genui = GenUIAdapter$new(data_env = genui_test_env()),
                   delegation_tools = FALSE, explore_data = FALSE)
  suppressWarnings(.register_all_tools(chat, settings))
  names <- vapply(chat$get_tools(), function(t) t@name, "")
  expect_setequal(names, c("Read", .genui_tool_names()))
})

test_that("canvas tools pass the central permission gate in plan mode", {
  for (tool in .genui_tool_names()) {
    expect_identical(check_permission(tool, mode = "plan"), "allow", info = tool)
  }
})

# -- prompt and reminder ---------------------------------------------------------

test_that("the system prompt carries the canvas section only with an adapter", {
  skip_if_no_genui()
  a <- GenUIAdapter$new(data_env = genui_test_env())
  with <- .build_system_prompt(list(genui = a), tempdir())
  without <- .build_system_prompt(list(), tempdir())
  expect_match(with, "## Canvas", fixed = TRUE)
  expect_false(grepl("## Canvas", without, fixed = TRUE))
})

test_that("the system prompt survives an unprepared adapter without blocking", {
  a <- GenUIAdapter$new(prepare = FALSE)
  local_mocked_bindings(.genui_build_catalog = function() stop("no catalog"))
  expect_no_error(.build_system_prompt(list(genui = a), tempdir()))
})

test_that("the reminder names live canvas components", {
  skip_if_no_genui()
  h <- genui_test_adapter()
  h$adapter$call("canvas_histogram", list(dataset = "cars", column = "mpg"))
  local_mocked_bindings(recall_memories_relevant = function(...) "")
  r <- .build_system_reminder(list(genui = h$adapter), iteration = 3L,
                              cwd = tempdir())
  expect_match(r, "c1 histogram (dataset cars)", fixed = TRUE)
})

# -- result routing --------------------------------------------------------------

test_that(".genui_artifact_result recognises canvas results", {
  skip_if_no_genui()
  h <- genui_test_adapter()
  res <- h$adapter$call("canvas_histogram", list(dataset = "cars", column = "mpg"))
  expect_true(.is_genui_result(res))
  expect_false(.is_genui_result(tool_result("x")))
})

# -- persistence ------------------------------------------------------------------

test_that("save_session writes the canvas state next to the chat state", {
  skip_if_no_genui()
  withr::local_envvar(HOME = withr::local_tempdir())
  cwd <- withr::local_tempdir()
  h <- genui_test_adapter()
  h$adapter$call("canvas_histogram", list(dataset = "cars", column = "mpg"))
  chat <- ellmer::chat_openai(model = "gpt-4.1", credentials = function() "test")
  chat$set_turns(list(ellmer::Turn("user", "hi")))
  sid <- save_session(chat, cwd, genui_state = h$adapter$snapshot(character()))
  state <- .read_session_genui_state(sid, cwd)
  expect_identical(state$schema, "codeagent.genui-state")
  expect_length(state$trace, 1L)
})

test_that("a session saved without a canvas reads back as NULL", {
  withr::local_envvar(HOME = withr::local_tempdir())
  cwd <- withr::local_tempdir()
  chat <- ellmer::chat_openai(model = "gpt-4.1", credentials = function() "test")
  chat$set_turns(list(ellmer::Turn("user", "hi")))
  sid <- save_session(chat, cwd)
  expect_null(.read_session_genui_state(sid, cwd))
})

test_that(".chat_request_ids lists every tool request id in the turns", {
  req <- ellmer::ContentToolRequest(id = "r1", name = "x", arguments = list())
  chat <- ellmer::chat_openai(model = "gpt-4.1", credentials = function() "test")
  chat$set_turns(list(ellmer::Turn("user", "hi"),
                      ellmer::AssistantTurn(contents = list(req))))
  expect_identical(.chat_request_ids(chat), "r1")
})

# -- restore ------------------------------------------------------------------------

test_that("restore rebuilds exactly the saved instances", {
  skip_if_no_genui()
  h <- genui_test_adapter()
  ellmer::with_tool_context(list(request = ellmer::ContentToolRequest(
    id = "r1", name = "canvas_histogram", arguments = list()), turns = list()),
    h$adapter$call("canvas_histogram", list(dataset = "cars", column = "mpg")))
  snap <- jsonlite::fromJSON(
    jsonlite::toJSON(h$adapter$snapshot("r1"), auto_unbox = TRUE, null = "null"),
    simplifyVector = FALSE)
  h2 <- genui_test_adapter(env = h$env)
  res <- h2$adapter$restore(snap, present_ids = "r1")
  expect_true(res$ok)
  expect_identical(h2$ops$dom, "ca_genui_shell_c1")
})

test_that("restore fails closed when the conversation lost the request", {
  skip_if_no_genui()
  h <- genui_test_adapter()
  ellmer::with_tool_context(list(request = ellmer::ContentToolRequest(
    id = "r1", name = "canvas_histogram", arguments = list()), turns = list()),
    h$adapter$call("canvas_histogram", list(dataset = "cars", column = "mpg")))
  snap <- h$adapter$snapshot("r1")
  h2 <- genui_test_adapter(env = h$env)
  res <- h2$adapter$restore(snap, present_ids = character())
  expect_false(res$ok)
  expect_match(res$message, "no longer matches")
  expect_identical(h2$ops$dom, character())
})

test_that("restore fails closed when the catalog digest changed", {
  skip_if_no_genui()
  h <- genui_test_adapter()
  h$adapter$call("canvas_histogram", list(dataset = "cars", column = "mpg"))
  snap <- h$adapter$snapshot(character())
  snap$catalog_digest <- "different"
  h2 <- genui_test_adapter(env = h$env)
  expect_match(h2$adapter$restore(snap)$message, "components changed")
})

test_that("restore fails closed when replay no longer validates", {
  skip_if_no_genui()
  h <- genui_test_adapter()
  h$adapter$call("canvas_histogram", list(dataset = "cars", column = "mpg"))
  snap <- h$adapter$snapshot(character())
  env2 <- genui_test_env(); env2$cars <- iris
  h2 <- genui_test_adapter(env = env2)
  res <- h2$adapter$restore(snap)
  expect_false(res$ok)
  expect_identical(h2$ops$dom, character())
})

test_that("restore never leaves a partial canvas when a mount fails", {
  skip_if_no_genui()
  h <- genui_test_adapter()
  h$adapter$call("canvas_histogram", list(dataset = "cars", column = "mpg"))
  h$adapter$call("canvas_histogram", list(dataset = "cars", column = "hp"))
  snap <- h$adapter$snapshot(character())
  h2 <- genui_test_adapter(env = h$env)
  h2$ops$fail_server <- function(module_id, args) identical(module_id, "ca_genui_c2")
  res <- h2$adapter$restore(snap)
  expect_false(res$ok)
  expect_identical(h2$ops$dom, character())
  expect_length(h2$adapter$state()$instances, 0L)
})

# -- rewind and cancellation -------------------------------------------------------

with_request <- function(id, code) {
  ellmer::with_tool_context(list(request = ellmer::ContentToolRequest(
    id = id, name = "canvas", arguments = list()), turns = list()), code)
}

test_that("forgetting a request rolls back its op and everything after it", {
  skip_if_no_genui()
  h <- genui_test_adapter()
  with_request("r1", h$adapter$call("canvas_histogram", list(dataset = "cars", column = "mpg")))
  with_request("r2", h$adapter$call("canvas_histogram", list(dataset = "cars", column = "hp")))
  with_request("r3", h$adapter$call("canvas_remove", list(id = "c1")))
  h$adapter$forget_requests(c("r2", "r3"))
  expect_identical(names(h$adapter$state()$instances), "c1")
  expect_identical(h$ops$dom, "ca_genui_shell_c1")
  expect_length(h$adapter$snapshot()$trace, 1L)
})

test_that("settle_turn drops only this turn's ops that never reached the chat", {
  skip_if_no_genui()
  h <- genui_test_adapter()
  with_request("r1", h$adapter$call("canvas_histogram", list(dataset = "cars", column = "mpg")))
  h$adapter$begin_turn()
  with_request("r2", h$adapter$call("canvas_histogram", list(dataset = "cars", column = "hp")))
  # r1 was compacted away long ago; it must not be touched.
  h$adapter$settle_turn(present_ids = character())
  expect_identical(names(h$adapter$state()$instances), "c1")
})

test_that("reset empties the canvas and its history", {
  skip_if_no_genui()
  h <- genui_test_adapter()
  h$adapter$call("canvas_histogram", list(dataset = "cars", column = "mpg"))
  h$adapter$reset()
  expect_identical(h$ops$dom, character())
  expect_length(h$adapter$snapshot()$trace, 0L)
})

test_that(".sync_genui_prompt adds, replaces and removes only its own section", {
  skip_if_no_genui()
  chat <- ellmer::chat_openai(model = "gpt-4.1", credentials = function() "test",
                              system_prompt = "# Intro\n\nhello\n\n# Host block\n\nkeep me")
  a <- GenUIAdapter$new(data_env = genui_test_env())
  .sync_genui_prompt(chat, list(genui = a))
  once <- chat$get_system_prompt()
  expect_match(once, "# Generative UI canvas", fixed = TRUE)
  .sync_genui_prompt(chat, list(genui = a))
  expect_identical(chat$get_system_prompt(), once)
  .sync_genui_prompt(chat, list())
  expect_identical(chat$get_system_prompt(),
                   "# Intro\n\nhello\n\n# Host block\n\nkeep me")
})

# -- Data Shield ---------------------------------------------------------------------

test_that("Data Shield redacts a protected value before it reaches the canvas", {
  skip_if_no_genui()
  sentinel <- "GENUIPROTECTED001"
  shield <- DataShield$new(strategies = list(shield_egress(max_rows = 0L), shield_regex()))
  shield$register_data(data.frame(id = c(sentinel, sprintf("GENUIPROTECTED%03d", 2:20))),
                       name = "protected")
  h <- genui_test_adapter()
  seen <- NULL
  h$ops$ops$run_server <- function(component, module_id, args, data) {
    seen <<- args
    NULL
  }
  h$adapter$bind(session = NULL, ops = h$ops$ops)
  chat <- ellmer::chat_openai(model = "gpt-4.1", credentials = function() "test")
  .register_genui_tools(chat, list(genui = h$adapter))
  shield$install(chat)
  tool <- Filter(function(t) identical(t@name, "canvas_histogram"), chat$get_tools())[[1]]
  res <- tool(dataset = "cars", column = "mpg", title = paste("Patient", sentinel))
  expect_false(is.null(seen))
  expect_false(grepl(sentinel, seen$title, fixed = TRUE))
  expect_false(grepl(sentinel, paste(capture.output(str(h$adapter$snapshot())),
                                     collapse = "\n"), fixed = TRUE))
})

test_that("canvas_state output passes Data Shield egress", {
  skip_if_no_genui()
  sentinel <- "GENUIPROTECTED001"
  shield <- DataShield$new(strategies = list(shield_egress(max_rows = 0L), shield_regex()))
  shield$register_data(data.frame(id = c(sentinel, sprintf("GENUIPROTECTED%03d", 2:20))),
                       name = "protected")
  h <- genui_test_adapter()
  h$adapter$call("canvas_histogram", list(dataset = "cars", column = "mpg"))
  # The user typed a protected value into the component's embedded input.
  h$ops$inputs[["ca_genui_c1"]] <- list(note = sentinel)
  chat <- ellmer::chat_openai(model = "gpt-4.1", credentials = function() "test")
  .register_genui_tools(chat, list(genui = h$adapter))
  shield$install(chat)
  tool <- Filter(function(t) identical(t@name, "canvas_state"), chat$get_tools())[[1]]
  res <- tool()
  value <- if (inherits(res, "ellmer::ContentToolResult")) res@value else res
  expect_false(grepl(sentinel, paste(value, collapse = ""), fixed = TRUE))
})
