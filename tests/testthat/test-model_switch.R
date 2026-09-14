# tests/testthat/test-model_switch.R
# Unit tests for lossless mid-conversation model switching (harness layer).

library(ellmer)

.mk_client <- function(turns = NULL) {
  ch <- chat_anthropic(model = "claude-sonnet-4-6")
  if (!is.null(turns)) ch$set_turns(turns)
  codeagent_client(ch, permission_mode = "bypass", btw_groups = NULL, cwd = getwd())
}

# ---------------------------------------------------------------------------
# Route A: in-place provider swap
# ---------------------------------------------------------------------------

test_that("switch_model Route A keeps the same Chat object + history", {
  cli <- .mk_client(list(Turn("user", "q1"), Turn("assistant", "a1")))
  old_chat <- cli$chat
  n_tools  <- length(cli$chat$get_tools())

  cli2 <- switch_model(cli, "anthropic/claude-haiku-4-5")

  expect_identical(cli2$chat, old_chat)                       # same object (Route A)
  expect_identical(cli2$settings$model, "claude-haiku-4-5")
  expect_identical(cli2$chat$get_model(), "claude-haiku-4-5")
  expect_length(cli2$chat$get_turns(), 2L)                    # history preserved
  expect_equal(length(cli2$chat$get_tools()), n_tools)        # tools preserved
  expect_false(is.null(cli2$chat$get_system_prompt()))        # sp preserved
})

test_that("switch_model Route A refreshes the worker backend snapshot", {
  cli <- .mk_client()
  cli$settings$worker_backend <- list(
    model = "claude-sonnet-4-6",
    provider = "anthropic",
    base_url = NULL,
    api_key_env = "CODEAGENT_API_KEY")
  captured <- NULL
  testthat::local_mocked_bindings(
    .register_all_tools = function(chat, settings, ask_fn = NULL, ...) {
      captured <<- settings$worker_backend
      invisible(chat)
    },
    .package = "codeagent"
  )
  out <- switch_model(cli, "anthropic/claude-haiku-4-5")
  expect_identical(out$settings$worker_backend$model,
                   "claude-haiku-4-5")
  expect_identical(captured$model, "claude-haiku-4-5")
})

test_that("switch_model preserves tool-call turns across the swap", {
  req <- ContentToolRequest(id = "c1", name = "weather",
                            arguments = list(city = "NYC"))
  res <- ContentToolResult(value = "sunny", request = req)
  cli <- .mk_client(list(
    Turn("user", "weather?"),
    Turn("assistant", contents = list(req)),
    Turn("user", contents = list(res))
  ))

  cli2 <- switch_model(cli, "anthropic/claude-haiku-4-5")
  t <- cli2$chat$get_turns()
  expect_length(t, 3L)
  expect_identical(t[[2]]@contents[[1]]@name, "weather")
  expect_identical(t[[3]]@contents[[1]]@request@id, "c1")
})

# ---------------------------------------------------------------------------
# Route B: fallback rebuild (force by stubbing .swap_provider to fail)
# ---------------------------------------------------------------------------

test_that("switch_model Route B rebuilds client when in-place swap fails", {
  cli <- .mk_client(list(Turn("user", "q1"), Turn("assistant", "a1")))
  cli$settings$worker_backend <- list(
    model = "claude-sonnet-4-6",
    provider = "anthropic",
    base_url = NULL,
    api_key_env = "CODEAGENT_API_KEY")
  old_chat <- cli$chat
  old_chat$set_system_prompt(paste0(
    old_chat$get_system_prompt(), "\n\nROUTE_B_RUNTIME_SENTINEL"))

  # Force Route B by making the provider swap fail.
  testthat::local_mocked_bindings(
    .swap_provider = function(chat, new_chat) FALSE,
    .package = "codeagent"
  )
  cli2 <- switch_model(cli, "anthropic/claude-haiku-4-5")

  expect_false(identical(cli2$chat, old_chat))                # NEW object (Route B)
  expect_identical(cli2$settings$model, "claude-haiku-4-5")
  expect_null(cli2$settings$worker_backend)
  expect_length(cli2$chat$get_turns(), 2L)                    # history migrated
  expect_gt(length(cli2$chat$get_tools()), 0L)               # tools re-registered
  names <- vapply(cli2$chat$get_tools(), function(tool) tool@name, character(1L))
  expect_true("Agent" %in% names)
  expect_false("TeamRun" %in% names)
  expect_match(cli2$chat$get_system_prompt(),
               "Process-based team/background delegation is unavailable")
  expect_false(grepl("TeamRun runs several", cli2$chat$get_system_prompt(),
                     fixed = TRUE))
  expect_match(cli2$chat$get_system_prompt(), "ROUTE_B_RUNTIME_SENTINEL")
  expect_match(cli2$chat$get_system_prompt(), "# Session\\n- Permission mode:")
  expect_false(grepl("# Sessionn-", cli2$chat$get_system_prompt(), fixed = TRUE))
})

test_that("switch_model never falls back after a fatal model rollback", {
  cli <- .mk_client()
  rebuild_calls <- 0L
  fatal <- structure(
    list(message = paste(
      "in-place model switch failed and model rollback also failed;",
      "restart the session."), call = NULL),
    class = c("codeagent_model_rollback_failure", "error", "condition"))
  testthat::local_mocked_bindings(
    .swap_provider = function(...) stop(fatal),
    .rebuild_client_for_model = function(...) {
      rebuild_calls <<- rebuild_calls + 1L
      stop("Route B must not run")
    },
    .package = "codeagent")

  expect_error(
    switch_model(cli, "anthropic/claude-haiku-4-5"),
    "restart the session",
    class = "codeagent_model_rollback_failure")
  expect_identical(rebuild_calls, 0L)
})

# ---------------------------------------------------------------------------
# Resolution + validation
# ---------------------------------------------------------------------------

test_that(".resolve_model_chat handles anthropic/ prefix", {
  ch <- .resolve_model_chat("anthropic/claude-haiku-4-5", cwd = getwd())
  expect_true(inherits(ch, "Chat"))
  expect_identical(ch$get_model(), "claude-haiku-4-5")
})

test_that("switch_model rejects bad inputs", {
  cli <- .mk_client()
  expect_error(switch_model("not a client", "anthropic/x"), "CodeagentClient")
  expect_error(switch_model(cli, ""), "non-empty")
  expect_error(switch_model(cli, character(0)), "non-empty")
})


# ---------------------------------------------------------------------------
# Strict Route A and lossless Route B regression coverage
# ---------------------------------------------------------------------------

test_that("Route A rejects same provider class with different endpoint", {
  old <- chat_openai_compatible(
    base_url = "https://one.invalid/v1", model = "m1",
    credentials = function() "placeholder")
  new <- chat_openai_compatible(
    base_url = "https://two.invalid/v1", model = "m2",
    credentials = function() "placeholder")

  expect_false(.swap_provider(old, new))
  expect_identical(old$get_model(), "m1")
  expect_identical(old$get_provider()@base_url, "https://one.invalid/v1")
})

test_that("Route A rejects Model params or extra_args changes", {
  old <- chat_anthropic(model = "same", params = list(temperature = 0.1),
                        api_args = list(metadata = list(source = "old")))
  changed_params <- chat_anthropic(
    model = "same", params = list(temperature = 0.2),
    api_args = list(metadata = list(source = "old")))
  changed_args <- chat_anthropic(
    model = "same", params = list(temperature = 0.1),
    api_args = list(metadata = list(source = "new")))

  expect_false(.swap_provider(old, changed_params))
  expect_false(.swap_provider(old, changed_args))
  expect_identical(old$get_model_object()@params$temperature, 0.1)
  expect_identical(old$get_model_object()@extra_args$metadata$source, "old")
})

test_that("Route B preserves complete live client state without rule re-merge", {
  shield <- DataShield$new(strategies = list(
    shield_regex(), shield_reviewer(model = "reviewer", on_risk = "block")))
  cli <- codeagent_client(
    chat_anthropic(model = "old"), permission_mode = "bypass",
    rules = list(PermissionRule("Read", "allow")), btw_groups = "docs",
    data_shield = shield, max_budget_usd = 2.5, cwd = getwd())
  cli$settings$async_subagents <- TRUE
  cli$settings$background_agents <- FALSE
  cli$settings$mcp_config <- list(mcpServers = list())
  cli$settings$custom_runtime_marker <- list(kept = TRUE)
  cli$settings$hooks_registry <- HookRegistry$new()
  old_rules <- cli$settings$rules
  old_hooks <- cli$settings$hooks_registry

  testthat::local_mocked_bindings(
    .resolve_model_chat = function(...) chat_openai_compatible(
      base_url = "https://route-b.invalid/v1", model = "new",
      credentials = function() "placeholder"),
    .package = "codeagent")
  out <- switch_model(cli, "openai/new")

  expect_false(identical(out$chat, cli$chat))
  expect_identical(out$data_shield, shield)
  expect_identical(out$settings$rules, old_rules)
  expect_identical(out$settings$hooks_registry, old_hooks)
  expect_identical(out$settings$max_budget_usd, 2.5)
  expect_identical(out$settings$mcp_config, list(mcpServers = list()))
  expect_true(out$data_shield$coverage()$reviewer_factory_bound)
  expect_true(out$settings$async_subagents)
  expect_identical(out$settings$custom_runtime_marker, list(kept = TRUE))
  expect_identical(out$chat$get_model_object()@name, "new")
})

test_that("client construction does not persistently set btw.client", {
  withr::local_options(list(btw.client = NULL))
  codeagent_client(chat_anthropic(model = "isolation"),
                   permission_mode = "bypass", btw_groups = NULL, cwd = getwd())
  expect_null(getOption("btw.client"))
})


test_that("Shiny model helper rejects running and Route B without mutation", {
  chat <- chat_anthropic(model = "old")
  settings <- list(model = "old")

  running <- .shiny_switch_model(chat, settings, "anthropic/new",
                                 running = TRUE)
  expect_false(running$ok)
  expect_identical(chat$get_model(), "old")

  testthat::local_mocked_bindings(
    .resolve_model_chat = function(...) chat_openai_compatible(
      base_url = "https://other.invalid/v1", model = "new",
      credentials = function() "placeholder"),
    .package = "codeagent")
  route_b <- .shiny_switch_model(chat, settings, "openai/new")
  expect_false(route_b$ok)
  expect_match(route_b$message, "new session|new provider", ignore.case = TRUE)
  expect_identical(chat$get_model(), "old")
})

test_that("Shiny model helper commits verified name-only switch", {
  chat <- chat_anthropic(model = "old")
  settings <- list(model = "old")
  testthat::local_mocked_bindings(
    .resolve_model_chat = function(...) chat_anthropic(model = "new"),
    .package = "codeagent")

  result <- .shiny_switch_model(chat, settings, "anthropic/new")
  expect_true(result$ok)
  expect_identical(result$model, "new")
  expect_identical(chat$get_model_object()@name, "new")
})


test_that("Route B build failure leaves original client untouched", {
  cli <- .mk_client(list(Turn("user", "keep me")))
  old_chat <- cli$chat
  old_model <- old_chat$get_model()
  testthat::local_mocked_bindings(
    .resolve_model_chat = function(...) chat_openai_compatible(
      base_url = "https://failure.invalid/v1", model = "new",
      credentials = function() "placeholder"),
    .register_all_tools = function(...) stop("forced rebuild failure"),
    .package = "codeagent")

  expect_error(switch_model(cli, "openai/new"), "forced rebuild failure")
  expect_identical(cli$chat, old_chat)
  expect_identical(cli$chat$get_model(), old_model)
  expect_length(cli$chat$get_turns(), 1L)
})


test_that("Route A accepts name-only change and preserves Model configuration", {
  credential <- function() "placeholder"
  old <- chat_openai_compatible(
    base_url = "https://same.invalid/v1", model = "m1",
    params = list(temperature = 0.2), api_args = list(seed = 7),
    credentials = credential)
  new <- chat_openai_compatible(
    base_url = "https://same.invalid/v1", model = "m2",
    params = list(temperature = 0.2), api_args = list(seed = 7),
    credentials = credential)

  expect_true(.swap_provider(old, new))
  expect_identical(old$get_model_object()@name, "m2")
  expect_identical(old$get_model_object()@params$temperature, 0.2)
  expect_identical(old$get_model_object()@extra_args$seed, 7)
})


test_that("Route A updates the managed prompt without a worker backend", {
  chat <- chat_anthropic(model = "old")
  client <- codeagent_client(chat, register_tools = FALSE, cwd = tempdir())
  expect_null(client$settings$worker_backend)
  testthat::local_mocked_bindings(
    .resolve_model_chat = function(...) chat_anthropic(model = "new"),
    .package = "codeagent")

  result <- .shiny_switch_model(client$chat, client$settings,
                                "anthropic/new", tempdir())
  expect_true(result$ok)
  expect_match(client$chat$get_system_prompt(), "Model: new")
  expect_false(grepl("Model: old", client$chat$get_system_prompt(), fixed = TRUE))
})

test_that("Route A refresh failure restores the previous system prompt", {
  chat <- chat_anthropic(model = "old")
  client <- codeagent_client(chat, register_tools = FALSE, cwd = tempdir())
  settings <- client$settings
  settings$worker_backend <- list(model = "old")
  old_prompt <- chat$get_system_prompt()
  chat$set_model("new")

  testthat::local_mocked_bindings(
    .register_all_tools = function(chat, ...) {
      chat$set_system_prompt("PARTIAL_NEW_PROMPT")
      stop("fixture late refresh failure")
    },
    .package = "codeagent")
  expect_error(
    .refresh_model_bound_tools(chat, settings),
    "fixture late refresh failure")
  expect_identical(chat$get_system_prompt(), old_prompt)
})


test_that("Route A reports a fatal error when tool rollback fails", {
  model_object <- chat_anthropic(model = "new")$get_model_object()
  old_tool <- ellmer::tool(function() "old", name = "OldTool",
                           description = "old", arguments = list())
  partial_tool <- ellmer::tool(function() "partial", name = "PartialTool",
                               description = "partial", arguments = list())
  chat <- new.env(parent = emptyenv())
  class(chat) <- c("Chat", "environment")
  chat$tools <- list(old_tool)
  chat$prompt <- "OLD_PROMPT"
  chat$get_model_object <- function() model_object
  chat$get_tools <- function() chat$tools
  chat$set_tools <- function(value) stop("fixture tool rollback failure")
  chat$get_system_prompt <- function() chat$prompt
  chat$set_system_prompt <- function(value) {
    chat$prompt <- value
    invisible(chat)
  }
  settings <- list(model = "new", worker_backend = list(model = "old"),
                   cwd = tempdir())

  testthat::local_mocked_bindings(
    .register_all_tools = function(chat, ...) {
      chat$tools <- list(partial_tool)
      chat$prompt <- "PARTIAL_PROMPT"
      stop("fixture refresh failure")
    },
    .package = "codeagent")
  expect_error(
    .refresh_model_bound_tools(chat, settings),
    "rollback also failed.*tools=FALSE.*restart")
  expect_identical(vapply(chat$get_tools(), function(x) x@name, character(1L)),
                   "PartialTool")
  expect_identical(chat$get_system_prompt(), "OLD_PROMPT")
})


test_that("in-place swap reports fatal when its internal rollback fails", {
  old_chat <- chat_anthropic(model = "old")
  new_chat <- chat_anthropic(model = "new")
  bad_model <- chat_anthropic(model = "unexpected")$get_model_object()
  make_chat <- function() {
    chat <- new.env(parent = emptyenv())
    class(chat) <- c("Chat", "environment")
    chat$current_model <- old_chat$get_model_object()
    chat$get_provider <- function() old_chat$get_provider()
    chat$get_model_object <- function() chat$current_model
    chat$set_model <- function(name) {
      if (identical(name, "new")) {
        chat$current_model <- bad_model
        return(invisible(chat))
      }
      stop("fixture internal rollback failure")
    }
    chat
  }

  direct <- make_chat()
  expect_error(
    .swap_provider(direct, new_chat),
    "rollback also failed.*restart",
    class = "codeagent_model_rollback_failure")
  expect_identical(direct$get_model_object()@name, "unexpected")

  shiny_chat <- make_chat()
  testthat::local_mocked_bindings(
    .resolve_model_chat = function(...) new_chat,
    .package = "codeagent")
  result <- .shiny_switch_model(
    shiny_chat, list(model = "old"), "anthropic/new", tempdir())
  expect_false(result$ok)
  expect_true(result$fatal)
  expect_match(result$message, "rollback also failed.*restart")
  expect_identical(shiny_chat$get_model_object()@name, "unexpected")
})


test_that("Shiny keeps refresh rollback failures fatal after model restore", {
  chat <- chat_anthropic(model = "old")
  new_chat <- chat_anthropic(model = "new")
  fatal <- structure(
    list(message = paste(
      "model refresh failed and rollback also failed (tools=FALSE, prompt=TRUE);",
      "restart the session."), call = NULL),
    class = c("codeagent_model_rollback_failure", "error", "condition"))
  testthat::local_mocked_bindings(
    .resolve_model_chat = function(...) new_chat,
    .refresh_model_bound_tools = function(...) stop(fatal),
    .package = "codeagent")

  result <- .shiny_switch_model(
    chat, list(model = "old"), "anthropic/new", tempdir())
  expect_false(result$ok)
  expect_true(result$fatal)
  expect_match(result$message, "rollback also failed.*restart")
  expect_identical(chat$get_model_object()@name, "old")
})


test_that("refresh rollback validates the complete model configuration", {
  old_chat <- chat_anthropic(model = "old", params = list(temperature = 0.1))
  new_chat <- chat_anthropic(model = "new", params = list(temperature = 0.1))
  corrupt_chat <- chat_anthropic(
    model = "old", params = list(temperature = 0.9))
  make_chat <- function() {
    chat <- new.env(parent = emptyenv())
    class(chat) <- c("Chat", "environment")
    chat$current_model <- old_chat$get_model_object()
    chat$get_provider <- function() old_chat$get_provider()
    chat$get_model_object <- function() chat$current_model
    chat$set_model <- function(name) {
      chat$current_model <- if (identical(name, "new"))
        new_chat$get_model_object()
      else corrupt_chat$get_model_object()
      invisible(chat)
    }
    chat
  }
  rebuild_calls <- 0L
  testthat::local_mocked_bindings(
    .resolve_model_chat = function(...) new_chat,
    .refresh_model_bound_tools = function(...) stop("fixture refresh failure"),
    .rebuild_client_for_model = function(...) {
      rebuild_calls <<- rebuild_calls + 1L
      stop("Route B must not run")
    },
    .package = "codeagent")

  shiny_chat <- make_chat()
  shiny_result <- .shiny_switch_model(
    shiny_chat, list(model = "old"), "anthropic/new", tempdir())
  expect_false(shiny_result$ok)
  expect_true(shiny_result$fatal)
  expect_match(shiny_result$message, "rollback both failed.*restart")
  expect_identical(shiny_chat$get_model_object()@name, "old")
  expect_identical(shiny_chat$get_model_object()@params$temperature, 0.9)

  sync_chat <- make_chat()
  client <- structure(
    list(chat = sync_chat, settings = list(cwd = tempdir(), model = "old"),
         data_shield = NULL),
    class = "CodeagentClient")
  expect_error(
    switch_model(client, "anthropic/new"),
    "rollback both failed.*restart",
    class = "codeagent_model_rollback_failure")
  expect_identical(rebuild_calls, 0L)
  expect_identical(sync_chat$get_model_object()@params$temperature, 0.9)
})
