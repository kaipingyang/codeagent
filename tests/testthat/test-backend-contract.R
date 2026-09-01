# Backend Contract v1 --- guard tests.
#
# codeagent exposes a documented, stable subset of its public API for host apps
# that embed it as a backend (see vignette "backend-integration"). These tests
# fail loudly if that contract drifts, so we do not silently break embedding
# hosts. If you intentionally change the contract, bump the version and update
# the vignette + these assertions together.

test_that("Backend Contract v1: the promised functions are exported", {
  v1 <- c(
    # entry + drive
    "codeagent_client", "codeagent_stream", "codeagent_stream_async", "agent_loop",
    # host tools + governance
    "register_tool_meta", "tool_result", "tool_result_artifact",
    "tool_result_value", "install_permission_gate",
    "DataShield", "shield_describe", "shield_egress", "shield_regex",
    "shield_ingress", "shield_tool_policy", "shield_sandbox", "shield_reviewer",
    # skills
    "list_skills_meta", "load_skill_prompt", "build_skill_hint",
    # context + model
    "CompactionController", "switch_model"
  )
  exports <- getNamespaceExports("codeagent")
  missing <- setdiff(v1, exports)
  expect_identical(missing, character(0),
                   info = paste("missing v1 exports:", paste(missing, collapse = ", ")))
})

test_that("Backend Contract v1: harness-only client registers no tools", {
  chat <- ellmer::chat_openai_compatible(
    base_url = "http://x", model = "m", credentials = function() "k")
  client <- codeagent_client(chat, register_tools = FALSE, cwd = getwd())

  expect_s3_class(client, "CodeagentClient")
  expect_true(!is.null(client$chat))
  expect_true(!is.null(client$settings))
  expect_null(client$data_shield)
  # The whole point of register_tools = FALSE: no coding tools attached.
  tools <- tryCatch(client$chat$get_tools(), error = function(e) list())
  expect_length(tools, 0L)
})

test_that("Backend Contract v1: streaming callback signature is stable", {
  fa <- names(formals(codeagent_stream_async))
  for (cb in c("on_delta", "on_thinking", "on_tool_request", "on_tool_result", "on_usage"))
    expect_true(cb %in% fa, info = paste("codeagent_stream_async missing", cb))
  expect_true("on_tick" %in% names(formals(codeagent_stream)))
})

test_that("Backend Contract v1: tool_result emits three separate channels", {
  tr <- tool_result("6 x 11 summary", kind = "table",
                     payload = list(df = utils::head(mtcars)), title = "Summary")
  expect_true(S7::S7_inherits(tr, ellmer::ContentToolResult))
  art <- tool_result_artifact(tr)
  expect_identical(art$schema, "codeagent.tool-artifact")
  expect_identical(art$version, 1L)
  expect_identical(art$kind, "table")
  expect_true(is.data.frame(art$payload$df))
  expect_identical(tool_result_value(tr), "6 x 11 summary")
  expect_s3_class(tr@extra$display, "shinychat_tool_result_display")
  # The UI-neutral artifact never lives under the shinychat display adapter.
  expect_null(tr@extra$display$toolcard)

  err <- tool_result("boom", kind = "error", payload = list(message = "boom"))
  expect_identical(tool_result_artifact(err)$status, "error")

  expect_error(tool_result(1, kind = "text"))            # value must be char(1)
  expect_error(tool_result("x", kind = "bogus"))         # kind validated
})

test_that("Backend Contract v1: host tools can be classified via register_tool_meta", {
  reg <- codeagent:::.tool_meta_user
  on.exit(rm(list = ls(reg), envir = reg), add = TRUE)
  expect_identical(codeagent:::.tool_capability("HostToolX"), "read")  # default benign
  register_tool_meta("HostToolX", "exec")
  expect_identical(codeagent:::.tool_capability("HostToolX"), "exec")  # now governed
})
