#!/usr/bin/env Rscript
# inst/examples/demo_05_shiny_app.R
#
# Demo: launch the codeagent Shiny app
#
# codeagent_app() supports three explicit entry styles (demonstrated below):
#   chat=           bare ellmer Chat template, cloned per Shiny session
#   client_factory= advanced per-session CodeagentClient factory
#   client=         pre-built mutable client (single-user compatibility)
#
# The Chat/template may use any ellmer backend:
#
#   chat_openai_compatible()  — Databricks / Azure / any OpenAI-compatible API
#   chat_anthropic()          — Anthropic API directly
#   chat_claude()             — alias for chat_anthropic()
#   chat_ollama()             — local Ollama
#   chat_google_gemini()      — Google Gemini
#   ... any ellmer chat_*() function
#
# If `chat` is omitted, codeagent_app() auto-builds one from env vars:
#   CODEAGENT_BASE_URL set  →  chat_openai_compatible()
#   CODEAGENT_BASE_URL unset →  chat_anthropic()
#
# Run from package root:
#   Rscript inst/examples/demo_05_shiny_app.R
# Or in RStudio:
#   source("inst/examples/demo_05_shiny_app.R")
#
# What to try in the app (a full walkthrough of the current UI):
#   Chat + tools
#   - Basic chat:   "List the R files in R/ directory"
#   - Tool use:     "Read R/utils.R and count how many functions it defines"
#   - ESC:          send a long prompt, press ESC to interrupt streaming
#   Slash commands (type "/" for the typeahead)
#   - /plan add a new tool     (skill -> injected prompt)
#   - /compact                 (compact the context now)
#   - /budget                  (show token usage)
#   - /model                   (popup model picker) ; /clear ; /rewind ; /sessions
#   Output panel (right, tabbed)
#   - Output: live tool-call results
#   - Files:  expand the tree, then click a file -> opens in the "File" tab
#             (syntax-highlighted code / rendered Markdown / image / CSV) with a
#             close (x) button
#   Sidebar accordions
#   - Sessions: New / Delete / click a saved session to load it (history replays)
#   - Customizations: Agents / Skills / Instructions / Hooks / MCP / Plugins modals
#   - Settings: permission mode, btw tool-group toggles, model switch
#   - top-right: light/dark mode toggle
#   Permission approval (switch Settings -> permission mode to "default")
#   - ask to create a file -> an Allow/Deny bar appears above the input
#   Startup: the UI shell renders instantly behind an "Initializing codeagent"
#   overlay while tools/skills load (chat input is gated until ready).

readRenviron(".Renviron")
devtools::load_all(quiet = TRUE)

# ---------------------------------------------------------------------------
# Step 1: Chat factory (any ellmer backend)
# ---------------------------------------------------------------------------
make_chat <- function() {
  ellmer::chat_openai_compatible(
    base_url    = Sys.getenv("CODEAGENT_BASE_URL"),
    model       = Sys.getenv("CODEAGENT_MODEL"),
    credentials = function() Sys.getenv("CODEAGENT_API_KEY")
  )
}
# Other providers work too:
# make_chat <- function() ellmer::chat_anthropic(model = "claude-sonnet-4-6")
# make_chat <- function() ellmer::chat_ollama(model = "llama3.2")

# ---------------------------------------------------------------------------
# Step 2: Choose ONE codeagent_app entry style
# ---------------------------------------------------------------------------
# Set CODEAGENT_APP_MODE=chat|factory|client; default = chat.
app_mode <- Sys.getenv("CODEAGENT_APP_MODE", "chat")
stopifnot(app_mode %in% c("chat", "factory", "client"))

cat("Launching codeagent_app mode:", app_mode, "\n")
cat("Press Ctrl-C to stop.\n\n")

if (identical(app_mode, "chat")) {
  # 1) Recommended convenience: bare ellmer Chat is a TEMPLATE. codeagent_app
  # clones it and builds a fresh CodeagentClient inside every Shiny session.
  codeagent_app(
    chat            = make_chat(),
    permission_mode = "bypass",
    btw_groups      = c("docs", "env", "pkg"),
    pinned_skills   = c("plan", "compact")
  )

} else if (identical(app_mode, "factory")) {
  # 2) Most flexible multi-user entry: dynamic credentials/models/session state.
  # Return a harness-only client so codeagent_app can lazily register tools under
  # its initialization overlay after the UI first renders.
  codeagent_app(
    client_factory = function(session) {
      codeagent_client(
        make_chat(), permission_mode = "bypass",
        btw_groups = c("docs", "env", "pkg"), register_tools = FALSE)
    },
    pinned_skills = c("plan", "compact")
  )

} else {
  # 3) Single-user compatibility: a fully pre-built mutable CodeagentClient is
  # reused as-is. Construction happens before the UI and skips lazy startup.
  prebuilt_client <- codeagent_client(
    make_chat(), permission_mode = "bypass",
    btw_groups = c("docs", "env", "pkg"))
  codeagent_app(
    client = prebuilt_client,
    pinned_skills = c("plan", "compact")
  )
}
