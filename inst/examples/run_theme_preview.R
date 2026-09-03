#!/usr/bin/env Rscript

# Preview codeagent's real Shiny UI with any built-in theme.
#
# Examples:
#   Rscript inst/examples/run_theme_preview.R --list
#   Rscript inst/examples/run_theme_preview.R aurora page_chat
#   Rscript inst/examples/run_theme_preview.R ios classic
#   Rscript inst/examples/run_theme_preview.R darkly page_chat 8888
#
# Opening the UI does not send a model request. Chat turns use your normal
# codeagent settings.

library(codeagent)

themes <- c("default", "ios", "aurora", "flatly", "darkly", "glass")
layouts <- c("page_chat", "classic")
args <- commandArgs(trailingOnly = TRUE)

if (identical(args, "--list")) {
  cat("Themes: ", paste(themes, collapse = ", "), "\n", sep = "")
  cat("Layouts: ", paste(layouts, collapse = ", "), "\n", sep = "")
  quit(save = "no")
}

theme_name <- if (length(args) >= 1L) args[[1L]] else "ios"
layout <- if (length(args) >= 2L) args[[2L]] else "page_chat"
port <- if (length(args) >= 3L) as.integer(args[[3L]]) else NULL
is_workbench <- any(nzchar(
  Sys.getenv(c("RS_SERVER_URL", "RS_SESSION_URL"))
))
host <- if (is_workbench) "0.0.0.0" else "127.0.0.1"

theme <- codeagent_theme(theme_name)
app <- codeagent_app(
  ui_layout = layout,
  theme = theme,
  launch.browser = FALSE
)

cat("Theme: ", theme_name, "\n", sep = "")
cat("Layout: ", layout, "\n", sep = "")

shiny::runApp(
  app,
  host = host,
  port = port,
  launch.browser = getOption("shiny.launch.browser", interactive())
)
