#!/usr/bin/env Rscript
# Deterministic installed-package app for the GenUI Chrome E2E gate
# (tests/e2e/verify-genui.R). No model or network is contacted.
#
# The fixture builds a conversation in which two canvas tool calls were made,
# computes the matching canvas state with a GenUIAdapter that has no browser,
# saves both with save_session(), clears the Chat, and lets codeagent_app()
# auto-continue that session -- so the browser sees the production restore
# path: strict replay, request-id binding and mounting into the Canvas tab.
#
# CODEAGENT_E2E_CASE:
#   restore  -- a consistent session; the canvas must come back
#   shielded -- the same with an active Data Shield
#   mismatch -- the canvas references a request the chat does not contain;
#               restore must fail closed and leave the canvas empty

required <- c("codeagent", "ellmer", "shiny", "shinygenui")
missing <- required[!vapply(required, requireNamespace, logical(1L), quietly = TRUE)]
if (length(missing))
  stop("Missing required installed packages: ", paste(missing, collapse = ", "),
       call. = FALSE)

case <- Sys.getenv("CODEAGENT_E2E_CASE", "restore")
if (!case %in% c("restore", "shielded", "mismatch"))
  stop("CODEAGENT_E2E_CASE must be restore, shielded or mismatch.", call. = FALSE)
ui_layout <- Sys.getenv("CODEAGENT_E2E_UI_LAYOUT", "classic")

fixture_root <- Sys.getenv("CODEAGENT_E2E_ROOT", "")
if (!nzchar(fixture_root))
  stop("CODEAGENT_E2E_ROOT must name an isolated writable directory.", call. = FALSE)
dir.create(fixture_root, recursive = TRUE, showWarnings = FALSE)
fixture_cwd <- file.path(normalizePath(fixture_root, winslash = "/"),
                         paste0("project-", case))
dir.create(fixture_cwd, recursive = TRUE, showWarnings = FALSE)

Sys.unsetenv(c("CODEAGENT_BASE_URL", "CODEAGENT_API_KEY", "CODEAGENT_MODEL",
               "OPENAI_API_KEY", "ANTHROPIC_API_KEY"))

# The data the canvas reads lives in the global environment, as it would after
# the model loaded it with RunR.
assign("e2e_cars", mtcars, envir = globalenv())

ns <- asNamespace("codeagent")
calls <- list(
  list(id = "e2e-canvas-1", tool = "canvas_histogram",
       args = list(dataset = "e2e_cars", column = "mpg",
                   title = "E2E_HISTOGRAM_TITLE")),
  list(id = "e2e-canvas-2", tool = "canvas_value_box",
       args = list(dataset = "e2e_cars", title = "E2E_VALUE_TITLE",
                   column = "hp", agg = "max"))
)

# A browserless adapter computes the trace the live app would have recorded.
null_ops <- list(
  insert = function(...) NULL, remove = function(...) NULL,
  null_output = function(...) NULL,
  run_server = function(...) NULL, input_values = function(...) NULL)
recorder <- ns$GenUIAdapter$new(data_env = globalenv())
recorder$bind(session = "fixture", ops = null_ops)
recorder$begin_turn()
turns <- list(ellmer::Turn("user", "E2E: show mpg and the top horsepower"))
for (call in calls) {
  request <- ellmer::ContentToolRequest(id = call$id, name = call$tool,
                                        arguments = call$args)
  result <- ellmer::with_tool_context(
    list(request = request, turns = list()),
    recorder$call(call$tool, call$args))
  if (!is.null(result@error)) stop("Fixture canvas call failed: ", result@error)
  result@request <- request
  turns <- c(turns, list(
    ellmer::AssistantTurn(contents = list(request)),
    ellmer::Turn("user", contents = list(result))))
}
turns <- c(turns, list(ellmer::AssistantTurn(
  contents = list(ellmer::ContentText("E2E_ASSISTANT_DONE")),
  finish_reason = "stop")))

present <- vapply(calls, `[[`, "", "id")
snapshot <- recorder$snapshot(present)
if (identical(case, "mismatch")) {
  # Keep the canvas but drop the second call from the conversation.
  turns <- turns[-c(4L, 5L)]
}

shield <- NULL
if (identical(case, "shielded")) {
  shield <- codeagent::DataShield$new(strategies = list(
    codeagent::shield_egress(max_rows = 0L), codeagent::shield_regex()))
  shield$register_data(data.frame(id = sprintf("E2EPROTECTED%03d", 1:20)),
                       name = "e2e_protected")
}

chat <- ellmer::chat_anthropic(model = "codeagent-e2e-local")
client <- codeagent::codeagent_client(
  chat = chat, permission_mode = "bypass", cwd = fixture_cwd,
  register_tools = FALSE, data_shield = shield,
  tools = c("Read", "genui"))
client$settings$auto_continue <- TRUE

chat$set_turns(turns)
codeagent::save_session(chat, cwd = fixture_cwd,
                        session_id = "00000000-0000-4000-8000-0000000000c1",
                        title = paste("GenUI E2E", case),
                        genui_state = snapshot)
chat$set_turns(list())

codeagent::codeagent_app(client, launch.browser = FALSE, ui_layout = ui_layout)
