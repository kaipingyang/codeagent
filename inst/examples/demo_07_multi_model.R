#!/usr/bin/env Rscript
# inst/examples/demo_07_multi_model.R
#
# Demo: LIVE model switching in the Shiny app.
#
# The left-sidebar "Model" dropdown (top-left) and the `/model` popup only offer
# choices when more than one model is configured. demo_05 builds its client from
# a single model, so its dropdown has just one entry (nothing to switch to).
#
# This demo wires up a `codeagent.md` config with several models so the dropdown
# lists them all -- pick another to switch live (chat history is preserved). The
# `/model <name>` command works too (e.g. `/model gsds-gpt-55`).
#
# Run from the package root:
#   Rscript inst/examples/demo_07_multi_model.R
# Or in RStudio / Positron:
#   source("inst/examples/demo_07_multi_model.R")
#
# What to try:
#   - Top-left "Model" dropdown -> pick "gpt55" / "deepseek-pro" -> a toast
#     confirms the switch; keep chatting, the conversation carries over.
#   - Type `/model gsds-deepseek-v4-flash` in the chat input to switch by name.
#   - Type `/model` (no arg) for the tier popup.

readRenviron(".Renviron")
devtools::load_all(quiet = TRUE)

# ---------------------------------------------------------------------------
# 1. Isolated working dir with a codeagent.md listing several models. Using a
#    dedicated dir keeps this demo from changing demo_05's single-model dropdown.
#    All specs are "openai/<model>", which resolves to chat_openai_compatible()
#    against CODEAGENT_BASE_URL (your serving endpoint) with CODEAGENT_API_KEY.
#    (Model names verified available on the gateway: gsds-gpt-54 / gsds-gpt-55 /
#    gsds-deepseek-v4-pro / gsds-deepseek-v4-flash. ai-gateway needs lowercase.)
# ---------------------------------------------------------------------------
demo_dir <- file.path(tempdir(), "codeagent_multimodel_demo")
dir.create(demo_dir, showWarnings = FALSE)

writeLines(c(
  "---",
  "client:",
  "  gpt54:          openai/gsds-gpt-54",
  "  gpt55:          openai/gsds-gpt-55",
  "  deepseek-pro:   openai/gsds-deepseek-v4-pro",
  "  deepseek-flash: openai/gsds-deepseek-v4-flash",
  "permission_mode: bypass",
  "btw_groups: [docs, env, pkg]",
  "---",
  "Follow tidyverse style."
), file.path(demo_dir, "codeagent.md"))

# A sample file so the Files tree / file viewer also have content to show.
writeLines(c(
  "#' Add two numbers",
  "#' @param a,b numeric",
  "add <- function(a, b) a + b",
  "",
  "#' Multiply two numbers",
  "mult <- function(a, b) a * b"
), file.path(demo_dir, "sample.R"))

# ---------------------------------------------------------------------------
# 2. Build the client from the first alias. The dropdown lists ALL configured
#    aliases, so you can switch to any of them from the UI.
# ---------------------------------------------------------------------------
client <- codeagent_client_config(alias = "gpt54", cwd = demo_dir)

# ---------------------------------------------------------------------------
# 3. Launch. Pass cwd = demo_dir so the dropdown reads this codeagent.md.
# ---------------------------------------------------------------------------
cat("Launching multi-model demo\n")
cat("  working dir:", demo_dir, "\n")
cat("  models:      gpt54 / gpt55 / deepseek-pro / deepseek-flash\n")
cat("  Try the top-left Model dropdown, or /model gsds-gpt-55\n")
codeagent_app(client, cwd = demo_dir, permission_mode = "bypass")
