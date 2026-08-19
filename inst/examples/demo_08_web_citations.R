#!/usr/bin/env Rscript
# Deterministic web citations in the Shiny app.
#
# The model receives stable source IDs from WebSearch/WebFetch and may emit only
# [[cite:SOURCE_ID|visible claim]]. codeagent buffers the reply, validates that
# the ID came from this turn, scans every field, and builds shiny-aside markup
# server-side. Provider/endpoint values remain environment-driven placeholders.

readRenviron(".Renviron")
devtools::load_all(quiet = TRUE)

chat <- ellmer::chat_openai_compatible(
  base_url = Sys.getenv("CODEAGENT_BASE_URL"),
  model = Sys.getenv("CODEAGENT_MODEL"),
  credentials = function() Sys.getenv("CODEAGENT_API_KEY"))

client <- codeagent_client(
  chat,
  permission_mode = "bypass",
  btw_groups = c("docs", "files"))

codeagent_app(client, web_citations = TRUE)
