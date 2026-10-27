#!/usr/bin/env Rscript
# inst/examples/demo_11_embed_host_app.R
#
# Demo: embed codeagent's chat engine in your own Shiny page.
#
# The host owns the layout (a sidebar chat beside its own panel) and one tool
# of its own; codeagent supplies streaming, the approval / question / form bar,
# skills, compaction and session saving through codeagent_server().
#
# Try: "Ask me which dataset and which columns to summarise, then summarise it"
# -- the model opens an AskUserForm in the chat, then calls the host tool.
#
# Run: Rscript inst/examples/demo_11_embed_host_app.R
# Needs CODEAGENT_BASE_URL / CODEAGENT_API_KEY (an OpenAI-compatible endpoint).

library(shiny)
library(bslib)
library(codeagent)

datasets <- list(mtcars = mtcars, iris = iris)

summarise_tool <- ellmer::tool(
  function(dataset, columns) {
    df <- datasets[[dataset]]
    if (is.null(df)) return(paste0("Unknown dataset: ", dataset))
    cols <- intersect(unlist(columns), names(df))
    ellmer::ContentToolResult(
      value = lapply(df[cols], function(x)
        if (is.numeric(x)) as.list(summary(x)) else as.list(table(x))),
      extra = list(display = list(title = paste("Summary of", dataset))))
  },
  name = "summarise_dataset",
  description = "Summarise selected columns of one of the host's datasets (mtcars, iris).",
  arguments = list(
    dataset = ellmer::type_enum(values = names(datasets), description = "Dataset name."),
    columns = ellmer::type_array("Columns to summarise.", items = ellmer::type_string())
  )
)

# The agent's instructions live in this directory's CLAUDE.md, not in ~/.claude.
agent_dir <- tempfile("host_agent_")
dir.create(agent_dir)
writeLines(c(
  "You help the user explore the host app's datasets (mtcars, iris).",
  "Before summarising, confirm dataset and columns with AskUserForm."
), file.path(agent_dir, "CLAUDE.md"))

ui <- page_sidebar(
  title = "Host app with codeagent",
  sidebar = sidebar(width = 420, codeagent_chat_ui(
    greeting = "Hi! Ask me to summarise **mtcars** or **iris**.")),
  card(card_header("Host panel"), "The host's own outputs go here."),
  codeagent_head_assets()
)

server <- function(input, output, session) {
  chat <- ellmer::chat_openai_compatible(
    base_url    = Sys.getenv("CODEAGENT_BASE_URL"),
    model       = Sys.getenv("CODEAGENT_MODEL", "gpt-4.1"),
    credentials = function() Sys.getenv("CODEAGENT_API_KEY"),
    echo        = "none")
  client <- codeagent_client(
    chat, cwd = agent_dir, permission_mode = "plan", register_tools = FALSE,
    tools = c("interact"),            # AskUserQuestion + AskUserForm only
    setting_sources = "project")
  codeagent_server(input, output, session, client,
                   tools = list(summarise_tool),
                   tool_meta = list(summarise_dataset = "read"))
}

shinyApp(ui, server)
