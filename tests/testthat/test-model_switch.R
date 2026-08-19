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
  old_chat <- cli$chat

  # Force Route B by making the provider swap fail.
  testthat::local_mocked_bindings(
    .swap_provider = function(chat, new_chat) FALSE,
    .package = "codeagent"
  )
  cli2 <- switch_model(cli, "anthropic/claude-haiku-4-5")

  expect_false(identical(cli2$chat, old_chat))                # NEW object (Route B)
  expect_identical(cli2$settings$model, "claude-haiku-4-5")
  expect_length(cli2$chat$get_turns(), 2L)                    # history migrated
  expect_gt(length(cli2$chat$get_tools()), 0L)               # tools re-registered
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
