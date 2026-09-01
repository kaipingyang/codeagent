#!/usr/bin/env Rscript
# Deterministic installed-package app for Plan 37 Chrome E2E verification.
#
# This fixture does not contact a model or web service. It creates a local
# ellmer Chat, writes one lossless codeagent session containing source metadata,
# clears the Chat, and lets codeagent_app() restore and present that session.

required <- c("codeagent", "ellmer", "shiny")
missing <- required[!vapply(required, requireNamespace, logical(1L), quietly = TRUE)]
if (length(missing)) {
  stop("Missing required installed packages: ", paste(missing, collapse = ", "),
       call. = FALSE)
}

case <- Sys.getenv("CODEAGENT_E2E_CASE", "core")
valid_cases <- c("core", "pass", "redact", "block")
if (!case %in% valid_cases) {
  stop("CODEAGENT_E2E_CASE must be one of: ",
       paste(valid_cases, collapse = ", "), call. = FALSE)
}
ui_layout <- Sys.getenv("CODEAGENT_E2E_UI_LAYOUT", "classic")
if (!ui_layout %in% c("classic", "page_chat")) {
  stop("CODEAGENT_E2E_UI_LAYOUT must be classic or page_chat.", call. = FALSE)
}

fixture_root <- Sys.getenv("CODEAGENT_E2E_ROOT", "")
if (!nzchar(fixture_root)) {
  stop("CODEAGENT_E2E_ROOT must name an isolated writable directory.",
       call. = FALSE)
}
dir.create(fixture_root, recursive = TRUE, showWarnings = FALSE)
fixture_root <- normalizePath(fixture_root, winslash = "/", mustWork = TRUE)
fixture_cwd <- file.path(fixture_root, paste0("project-", case))
dir.create(fixture_cwd, recursive = TRUE, showWarnings = FALSE)
writeLines("E2E_FILE_CONTENT", file.path(fixture_cwd, "e2e-visible.txt"))
writeLines("E2E_REOPEN_CONTENT", file.path(fixture_cwd, "e2e-reopen.txt"))

# Do not let ambient credentials or provider configuration influence this app.
Sys.unsetenv(c(
  "CODEAGENT_BASE_URL", "CODEAGENT_API_KEY", "CODEAGENT_MODEL",
  "CODEAGENT_FAST_MODEL", "CODEAGENT_HEAVY_MODEL", "OPENAI_API_KEY",
  "ANTHROPIC_API_KEY", "GOOGLE_API_KEY", "BRAVE_API_KEY"
))

all_groups <- sort(names(codeagent:::.BTW_GROUPS))
if (!length(all_groups)) {
  stop("Installed codeagent exposes no btw tool groups.", call. = FALSE)
}

sentinel <- "E2EPROTECTED123"
shield <- NULL
if (!identical(case, "core")) {
  shield <- codeagent::DataShield$new(strategies = list(
    codeagent::shield_egress(max_rows = 0L),
    codeagent::shield_regex()))
  shield$register_data(data.frame(
    id = c(sentinel, sprintf("E2EPROTECTED%03d", 1:20))),
    name = "e2e")
}

chat <- ellmer::chat_anthropic(model = "codeagent-e2e-local")
client <- codeagent::codeagent_client(
  chat = chat,
  permission_mode = "bypass",
  cwd = fixture_cwd,
  btw_groups = all_groups,
  register_tools = FALSE,
  data_shield = shield
)
client$settings$auto_continue <- TRUE
client$settings$web_citations <- "shiny_aside"
client$settings$data_shield_output_scanners <- "value_match"
client$settings$data_shield_response_on_fail <-
  if (identical(case, "block")) "block" else "redact"

source <- codeagent:::.new_web_source(
  url = "https://example.com/codeagent-e2e",
  title = "Deterministic E2E source",
  cited_quote = "A local fixture quote used without a network request.",
  tool = "WebFetch",
  id = "src_e2e00001"
)
fixture_tool <- ellmer::tool(
  function(url, prompt = NULL) "Local deterministic source fixture.",
  name = "WebFetch",
  description = "Local deterministic source fixture; never executed.",
  arguments = list(
    url = ellmer::type_string("Fixture URL", required = TRUE),
    prompt = ellmer::type_string("Optional fixture prompt", required = FALSE))
)
fixture_request <- ellmer::ContentToolRequest(
  id = paste0("e2e-web-fetch-", case),
  name = "WebFetch",
  arguments = list(url = source$url),
  tool = fixture_tool
)
source_result <- ellmer::ContentToolResult(
  value = "Local deterministic source fixture.",
  request = fixture_request,
  extra = list(
    display = shinychat::tool_result_display(
      title = "Deterministic source artifact",
      html = htmltools::tags$pre("E2E_FRAMED_ARTIFACT"),
      open_style = "framed"
    ),
    codeagent = list(sources = list(source, source))
  )
)

assistant_text <- switch(
  case,
  core = paste0(
    "E2E_CASE_CORE: grounded evidence ",
    "[[cite:src_e2e00001|grounded evidence]] and grounded evidence ",
    "[[cite:src_e2e00001|grounded evidence]]"),
  pass = paste0(
    "E2E_CASE_PASS: safe evidence ",
    "[[cite:src_e2e00001|safe grounded evidence]]"),
  redact = paste0(
    "E2E_CASE_REDACT: ",
    "[[cite:src_e2e00001|protected claim ", sentinel, "]]"),
  block = paste0(
    "E2E_CASE_BLOCK: ",
    "[[cite:src_e2e00001|blocked claim ", sentinel, "]]"))

chat$set_turns(list(
  ellmer::Turn("user", paste("E2E fixture question for", case)),
  ellmer::Turn("user", contents = list(source_result)),
  ellmer::AssistantTurn(
    contents = list(ellmer::ContentText(assistant_text)),
    finish_reason = "stop")
))

# Exercise the production ordering used after a live buffered response:
# citation rebuild -> full-response output gate -> presentation override save.
# save_session() deliberately keeps the raw assistant turn in lossless chat-state
# while writing the finalized text to the presentation line. Restoring the saved
# session must therefore remain safe even though the raw turn still has a marker
# (and, for redact/block, the protected sentinel).
citation_registry <- codeagent:::.new_citation_registry()
codeagent:::.citation_registry_add(
  citation_registry, codeagent:::.citation_sources_from_result(source_result))
finalized <- codeagent:::.finalize_server_reply(
  chat, client$settings, citation_registry)
if (grepl("[[cite:", finalized$text, fixed = TRUE) ||
    grepl(sentinel, finalized$text, fixed = TRUE)) {
  stop("Production finalizer exposed a raw marker or protected sentinel.",
       call. = FALSE)
}
if (identical(case, "block")) {
  if (!grepl("block", finalized$text, ignore.case = TRUE)) {
    stop("Production finalizer did not produce an assertable block result.",
         call. = FALSE)
  }
} else if (!grepl("<shiny-aside", finalized$text, fixed = TRUE)) {
  stop("Production finalizer did not build the deterministic citation aside.",
       call. = FALSE)
}
raw_assistant <- tryCatch(chat$last_turn(role = "assistant")@text,
                          error = function(e) "")
if (case %in% c("redact", "block") &&
    !grepl(sentinel, raw_assistant, fixed = TRUE)) {
  stop("Fixture no longer retains a raw protected lossless assistant turn.",
       call. = FALSE)
}

session_id <- switch(
  case,
  core = "00000000-0000-4000-8000-000000000001",
  pass = "00000000-0000-4000-8000-000000000002",
  redact = "00000000-0000-4000-8000-000000000003",
  block = "00000000-0000-4000-8000-000000000004")
codeagent::save_session(
  chat,
  cwd = fixture_cwd,
  session_id = session_id,
  title = paste("E2E fixture", case),
  assistant_text_override = finalized$text
)
chat$set_turns(list())

chat$register_tool(fixture_tool)

# Core must both retain the replay tool and make codeagent's first readiness
# check observe an empty tool set. A one-shot instance override does exactly
# that: the first server check returns empty, then every later call delegates to
# the original Chat method. Deferred registration and lossless restore therefore
# exercise their production paths without a provider or a timing sleep.
if (identical(case, "core")) {
  original_get_tools <- chat$get_tools
  first_tools_check <- TRUE
  if (!bindingIsLocked("get_tools", chat)) {
    stop("Unexpected ellmer Chat method binding state.", call. = FALSE)
  }
  unlockBinding("get_tools", chat)
  assign("get_tools", function(...) {
    if (isTRUE(first_tools_check)) {
      first_tools_check <<- FALSE
      return(list())
    }
    original_get_tools(...)
  }, envir = chat)
  lockBinding("get_tools", chat)
}

factory <- function(session) client
codeagent::codeagent_app(
  client_factory = factory,
  permission_mode = "bypass",
  cwd = fixture_cwd,
  btw_groups = all_groups,
  ui_layout = ui_layout,
  web_citations = "shiny_aside",
  launch.browser = FALSE
)
