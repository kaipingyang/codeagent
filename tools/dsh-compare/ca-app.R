# codeagent app for the DSH comparison: talks to the local mock model only.
# Rscript ca-app.R <theme> <ui_layout> <port> <project_dir>
# A client factory gives every browser session its own Chat, as DSH does; tools
# are registered per session (register_tools = FALSE) so approvals reach the UI.
args <- commandArgs(trailingOnly = TRUE)
theme <- args[[1]]; layout <- args[[2]]; port <- as.integer(args[[3]]); project <- args[[4]]
# R reads the real ~/.Renviron before HOME is swapped; override what it set.
Sys.unsetenv(c("CODEAGENT_API_KEY", "CODEAGENT_BASE_URL", "CODEAGENT_HEAVY_MODEL",
               "CODEAGENT_FAST_MODEL", "OPENAI_API_KEY", "ANTHROPIC_API_KEY"))
Sys.setenv(CODEAGENT_MODEL = "mock-model")
home <- file.path(dirname(project), "ca-home")
unlink(home, recursive = TRUE)
Sys.setenv(CODEAGENT_HOME = home)
factory <- function() {
  chat <- ellmer::chat_openai_compatible(
    base_url = Sys.getenv("DSH_COMPARE_MOCK", "http://127.0.0.1:18080/v1"),
    model = "mock-model", credentials = function() "mock")
  codeagent::codeagent_client(chat, permission_mode = "default", cwd = project,
    tools = c("Read", "Bash", "AskUserQuestion"), register_tools = FALSE)
}
app <- codeagent::codeagent_app(client_factory = factory, theme = theme,
                                ui_layout = layout, launch.browser = FALSE)
shiny::runApp(app, port = port, launch.browser = FALSE)
