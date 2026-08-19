tool_names <- function(tools) {
  vapply(tools, function(tool) tool@name, character(1L))
}

fake_tool <- function(name) {
  ellmer::tool(
    function(value = "") paste(name, value),
    name = name,
    description = paste("fixture", name),
    arguments = list(value = ellmer::type_string("value", required = FALSE))
  )
}

fake_tool_chat <- function(tools, fail = c("never", "once", "always")) {
  fail <- match.arg(fail)
  chat <- new.env(parent = emptyenv())
  class(chat) <- c("Chat", "environment")
  chat$tools <- tools
  chat$set_calls <- 0L
  chat$get_tools <- function() chat$tools
  chat$set_tools <- function(value) {
    chat$set_calls <- chat$set_calls + 1L
    chat$tools <- value
    if (identical(fail, "always") || (identical(fail, "once") && chat$set_calls == 1L))
      stop("fixture set_tools failure")
    invisible(chat)
  }
  chat
}

with_btw_group_fixtures <- function(code) {
  testthat::local_mocked_bindings(
    .btw_selected_tools = function(groups = NULL, include_agent = TRUE) {
      available <- list(
        docs = fake_tool("btw_tool_docs_help"),
        env = fake_tool("btw_tool_env_describe"),
        git = fake_tool("btw_tool_git_status")
      )
      if (is.null(groups)) return(unname(available))
      unname(available[intersect(groups, names(available))])
    },
    .collect_dedicated_agent_tools = function(...) list(fake_tool("Agent")),
    .btw_replaceable_names = function() c(
      "btw_tool_docs_help", "btw_tool_env_describe", "btw_tool_git_status")
  )
  force(code)
}

test_that("btw groups replace atomically all -> docs -> none while preserving owners", {
  with_btw_group_fixtures({
    chat <- fake_tool_chat(list(
      fake_tool("Read"), fake_tool("MCP_demo"), fake_tool("use_skill"),
      fake_tool("Agent"), fake_tool("btw_tool_docs_help"),
      fake_tool("btw_tool_env_describe"), fake_tool("btw_tool_git_status")
    ))
    settings <- list(cwd = tempdir(), permission_mode = "default")

    docs <- .replace_btw_tool_groups(chat, "docs", settings)
    expect_true(docs$ok)
    expect_setequal(tool_names(chat$get_tools()),
                    c("Read", "MCP_demo", "use_skill", "btw_tool_docs_help"))

    none <- .replace_btw_tool_groups(chat, character(), settings)
    expect_true(none$ok)
    expect_setequal(tool_names(chat$get_tools()), c("Read", "MCP_demo", "use_skill"))
    expect_identical(chat$set_calls, 2L)
  })
})

test_that("agent checkbox alone controls the dedicated Agent owner", {
  with_btw_group_fixtures({
    chat <- fake_tool_chat(list(fake_tool("Read"), fake_tool("Agent")))
    settings <- list(cwd = tempdir(), permission_mode = "default")
    expect_true(.replace_btw_tool_groups(chat, "agent", settings)$ok)
    expect_true("Agent" %in% tool_names(chat$get_tools()))
    expect_true(.replace_btw_tool_groups(chat, "docs", settings)$ok)
    expect_false("Agent" %in% tool_names(chat$get_tools()))
  })
})

test_that("btw replacement applies input hook before Data Shield without nesting", {
  with_btw_group_fixtures({
    shield <- structure(new.env(parent = emptyenv()), class = "DataShield")
    hooks <- new.env(parent = emptyenv())
    hooks$run_pre <- function(...) NULL
    chat <- fake_tool_chat(list(fake_tool("Read")))
    attr(chat, "codeagent_data_shield") <- shield
    settings <- list(cwd = tempdir(), hooks_registry = hooks,
                     data_shield_engine = shield)
    expect_true(.replace_btw_tool_groups(chat, "docs", settings)$ok)
    tool <- chat$get_tools()[[match("btw_tool_docs_help", tool_names(chat$get_tools()))]]
    outer <- S7::S7_data(tool)
    expect_identical(get0(".codeagent_data_shield_state", environment(outer),
                          inherits = FALSE), shield)
    inner <- get0(".codeagent_data_shield_original", environment(outer),
                  inherits = FALSE)
    expect_identical(get0(".codeagent_pre_hook_state", environment(inner),
                          inherits = FALSE), hooks)
    again <- .data_shield_wrap_tool(tool, shield)
    expect_identical(S7::S7_data(again), outer)
  })
})

test_that("failed atomic replacement restores the exact old snapshot", {
  with_btw_group_fixtures({
    old <- list(fake_tool("Read"), fake_tool("btw_tool_env_describe"), fake_tool("Agent"))
    chat <- fake_tool_chat(old, fail = "once")
    result <- .replace_btw_tool_groups(chat, "docs", list(cwd = tempdir()))
    expect_false(result$ok)
    expect_true(result$restored)
    expect_identical(chat$get_tools(), old)
    expect_identical(chat$set_calls, 2L)
  })
})

test_that("rollback failure is reported fatal so the UI can disable input", {
  with_btw_group_fixtures({
    chat <- fake_tool_chat(list(fake_tool("Read")), fail = "always")
    result <- .replace_btw_tool_groups(chat, "docs", list(cwd = tempdir()))
    expect_false(result$ok)
    expect_false(result$restored)
    expect_true(result$fatal)
  })
})

test_that("stream running detection is fail-safe and deterministic", {
  expect_false(.stream_is_running(NULL))
  expect_true(.stream_is_running(list(status = function() "running")))
  expect_false(.stream_is_running(list(status = function() "idle")))
  expect_false(.stream_is_running(list(status = function() stop("broken"))))
})


test_that("real btw snapshot removes deselected groups", {
  chat <- ellmer::chat_anthropic(model = "fixture")
  chat$register_tool(fake_tool("CoreFixture"))
  settings <- list(cwd = tempdir(), permission_mode = "default",
                   rules = list(), async_subagents = FALSE,
                   worktree_isolation = FALSE)

  all <- .replace_btw_tool_groups(chat, NULL, settings)
  expect_true(all$ok)
  all_names <- tool_names(chat$get_tools())
  expect_true(any(startsWith(all_names, "btw_tool_docs_")))
  expect_true(any(all_names == "Agent" | startsWith(all_names, "btw_tool_agent_")))

  docs <- .replace_btw_tool_groups(chat, "docs", settings)
  expect_true(docs$ok)
  docs_names <- tool_names(chat$get_tools())
  expect_true(any(startsWith(docs_names, "btw_tool_docs_")))
  expect_false(any(startsWith(docs_names, "btw_tool_env_")))
  expect_false(any(docs_names == "Agent" | startsWith(docs_names, "btw_tool_agent_")))
  expect_true("CoreFixture" %in% docs_names)

  none <- .replace_btw_tool_groups(chat, character(), settings)
  expect_true(none$ok)
  expect_identical(unname(tool_names(chat$get_tools())), "CoreFixture")
})


test_that("settings observers reject permission and group mutation while streaming", {
  registrations <- 0L
  replacements <- 0L
  testthat::local_mocked_bindings(
    .register_all_tools = function(...) { registrations <<- registrations + 1L },
    .replace_btw_tool_groups = function(...) {
      replacements <<- replacements + 1L
      list(ok = TRUE)
    },
    .ui_toast = function(...) invisible(NULL),
    list_skills_meta = function(...) list()
  )
  chat <- fake_tool_chat(list(fake_tool("Read")))
  settings <- list(permission_mode = "default", data_shield_engine = NULL)
  stream <- list(status = function() "running")
  wrapped_server <- function(input, output, session) {
    server_settings(input, output, session, chat = chat, settings = settings,
                    cwd = tempdir(), hooks = NULL, stream_task = stream)
  }
  shiny::testServer(
    wrapped_server,
    {
      session$setInputs(perm_mode = "plan")
      session$setInputs(btw_groups_input = "docs")
      session$flushReact()
    }
  )
  expect_identical(registrations, 0L)
  expect_identical(replacements, 0L)
})


test_that("settings observer applies an empty tool-group selection", {
  replacements <- list()
  testthat::local_mocked_bindings(
    .replace_btw_tool_groups = function(chat, groups, settings) {
      replacements[[length(replacements) + 1L]] <<- groups
      list(ok = TRUE)
    },
    .ui_toast = function(...) invisible(NULL),
    list_skills_meta = function(...) list()
  )
  chat <- fake_tool_chat(list(fake_tool("Read")))
  settings <- list(permission_mode = "default", btw_groups = "docs",
                   data_shield_engine = NULL)
  wrapped_server <- function(input, output, session) {
    server_settings(input, output, session, chat = chat, settings = settings,
                    cwd = tempdir(), hooks = NULL, stream_task = NULL)
  }
  shiny::testServer(
    wrapped_server,
    {
      session$setInputs(btw_groups_input = "docs")
      session$flushReact()
      session$setInputs(btw_groups_input = character())
      session$flushReact()
    }
  )
  expect_length(replacements, 1L)
  expect_identical(replacements[[1L]], character())
})
