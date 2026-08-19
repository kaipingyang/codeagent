# Security regressions for foreground sub-agents under Data Shield.

.subagent_test_shield <- function() {
  shield <- DataShield$new(strategies = list(
    shield_describe(), shield_egress(max_rows = 0)))
  shield$register_data(
    data.frame(subject_id = paste0("SUBSECRET", sprintf("%03d", 1:12))),
    name = "study")
  shield
}

test_that("full shield client exposes no raw btw subagent", {
  skip_if_not_installed("btw")
  shield <- .subagent_test_shield()
  chat <- ellmer::chat_openai_compatible(
    base_url = "https://example.invalid/v1", model = "placeholder",
    credentials = function() "placeholder")

  client <- suppressWarnings(codeagent_client(
    chat, permission_mode = "bypass",
    cwd = tempdir(), data_shield = shield))
  names <- vapply(client$chat$get_tools(), function(tool) tool@name, character(1))

  expect_true("Agent" %in% names)
  expect_false(any(grepl("^btw_tool_agent_", names)))
})

test_that("shielded sync subagent gates output before persistence", {
  shield <- .subagent_test_shield()
  saved <- FALSE
  fake_chat <- list(chat = function(prompt) "answer SUBSECRET007")

  testthat::local_mocked_bindings(
    save_session = function(...) { saved <<- TRUE; invisible(NULL) },
    .package = "codeagent")

  out <- codeagent:::.run_subagent_loop(
    fake_chat, "prompt", persist = TRUE, cwd = tempdir(),
    description = "safe", data_shield = shield)

  expect_false(grepl("SUBSECRET007", out, fixed = TRUE))
  expect_false(saved)
})

test_that("shielded async subagent gates output before persistence", {
  skip_if_not_installed("promises")
  shield <- .subagent_test_shield()
  saved <- FALSE
  fake_chat <- list(chat_async = function(prompt) {
    promises::promise_resolve("answer SUBSECRET007")
  })

  testthat::local_mocked_bindings(
    save_session = function(...) { saved <<- TRUE; invisible(NULL) },
    .package = "codeagent")

  value <- NULL
  done <- FALSE
  p <- codeagent:::.run_subagent_loop_async(
    fake_chat, "prompt", persist = TRUE, cwd = tempdir(),
    description = "safe", data_shield = shield)
  promises::then(p, function(x) { value <<- x; done <<- TRUE })
  for (i in seq_len(200L)) {
    later::run_now(0.01)
    if (done) break
  }

  expect_true(done)
  expect_false(grepl("SUBSECRET007", value, fixed = TRUE))
  expect_false(saved)
})

test_that("SubagentStop hook only receives gated output", {
  shield <- .subagent_test_shield()
  captured <- NULL
  hooks <- HookRegistry$new()
  hooks$register(HookEvent$SUBAGENT_STOP, function(description, result, context) {
    captured <<- result
  })
  sub_chat <- ellmer::chat_openai_compatible(
    base_url = "https://example.invalid/v1", model = "placeholder",
    credentials = function() "placeholder")

  testthat::local_mocked_bindings(
    .make_chat = function(...) sub_chat,
    register_builtin_tools = function(chat, ...) invisible(chat),
    .run_subagent_loop = function(...) "answer SUBSECRET007",
    .package = "codeagent")

  out <- agent_tool(data_shield = shield, hooks = hooks)(
    description = "safe", prompt = "prompt")

  expect_false(grepl("SUBSECRET007", out, fixed = TRUE))
  expect_false(grepl("SUBSECRET007", captured, fixed = TRUE))
})


test_that("asset audit stores stable reason codes, not caller text", {
  sentinel <- "PRIVATE_REASON_SENTINEL"
  shield <- DataShield$new(strategies = list(shield_regex()))
  shield$register_asset(
    "public reference", name = "spec", kind = "spec",
    llm_access = list(prompt = "raw", egress = "raw"),
    scan_secrets = FALSE, reason = sentinel)

  expect_equal(shield$prompt_content("spec"), "public reference")
  audit <- shield$audit()
  serialized <- jsonlite::toJSON(audit, dataframe = "rows", auto_unbox = TRUE)
  expect_false(grepl(sentinel, serialized, fixed = TRUE))
  expect_true(any(audit$reason == "approved_asset_policy"))
})
