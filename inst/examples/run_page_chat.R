#!/usr/bin/env Rscript

library(codeagent)

# Examples:
#   Rscript inst/examples/run_page_chat.R
#   CODEAGENT_UI_THEME=aurora Rscript inst/examples/run_page_chat.R
theme <- Sys.getenv("CODEAGENT_UI_THEME", "default")
is_workbench <- any(nzchar(
  Sys.getenv(c("RS_SERVER_URL", "RS_SESSION_URL"))
))
host <- if (is_workbench) "0.0.0.0" else "127.0.0.1"

app <- codeagent_app(
  ui_layout = "page_chat",
  theme = theme,
  launch.browser = FALSE
)

shiny::runApp(
  app,
  host = host,
  launch.browser = getOption("shiny.launch.browser", interactive())
)
