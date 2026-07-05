#!/usr/bin/env Rscript
# inst/examples/demo_05_shiny_app.R
#
# Demo: launch the codeagent Shiny app
#
# codeagent_app() accepts an optional `chat` argument — any ellmer Chat object.
# Create the Chat yourself so you can use any ellmer backend:
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
# What to try in the app:
#   - Basic chat: "List the R files in R/ directory"
#   - Tool use:   "Read R/utils.R and count how many functions it defines"
#   - Skill:      "/plan add a new tool to the package"
#   - Skill:      "/compact"
#   - Permission: switch to 'plan' mode, then ask to create a file (should deny)
#   - ESC:        send a long prompt, press ESC to interrupt streaming

readRenviron(".Renviron")
devtools::load_all(quiet = TRUE)

# ---------------------------------------------------------------------------
# Step 1: Create an ellmer Chat (any backend you want)
# ---------------------------------------------------------------------------

# Option A: Databricks / OpenAI-compatible endpoint
chat <- ellmer::chat_openai_compatible(
  base_url    = Sys.getenv("CODEAGENT_BASE_URL"),
  model       = Sys.getenv("CODEAGENT_MODEL"),
  credentials = function() Sys.getenv("CODEAGENT_API_KEY")
)

# Option B: Anthropic API (uncomment to use)
# chat <- ellmer::chat_anthropic(model = "claude-sonnet-4-6")

# Option C: Local Ollama (uncomment to use)
# chat <- ellmer::chat_ollama(model = "llama3.2")

# ---------------------------------------------------------------------------
# Step 2: Wrap into a codeagent client (injects tools + system prompt)
# ---------------------------------------------------------------------------
client <- codeagent_client(
  chat,
  permission_mode = "bypass",
  btw_groups      = c("docs", "env", "pkg"),
  cwd             = getwd()
)

# ---------------------------------------------------------------------------
# Step 3: Launch the app (pure UI params only)
# ---------------------------------------------------------------------------
cat(sprintf("Launching codeagent_app with: %s\n", client$settings$model))
cat("Press Ctrl-C to stop.\n\n")

codeagent_app(
  client,
  pinned_skills = c("plan", "compact")
)
