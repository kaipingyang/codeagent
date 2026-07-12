#!/usr/bin/env Rscript
# inst/examples/demo_01_basic_chat.R
#
# Demo: basic one-shot chat with three Databricks models
#
# Two styles shown:
#   Legacy:  codeagent(prompt, model=..., permission_mode=...)
#   New:     client <- codeagent_client(chat, ...); codeagent(client, prompt)
#
# Run from package root: Rscript inst/examples/demo_01_basic_chat.R

devtools::load_all(quiet = TRUE)

cat("=== Demo 1: Basic Chat ===\n\n")

models <- strsplit(Sys.getenv("CODEAGENT_MODELS", "gpt-4.1"), ",")[[1]]

for (model in models) {
  cat(sprintf("--- %s (new style) ---\n", model))

  # New style: explicit chat factory → codeagent_client → codeagent
  chat <- ellmer::chat_openai_compatible(
    base_url    = Sys.getenv("CODEAGENT_BASE_URL"),
    model       = model,
    credentials = function() Sys.getenv("CODEAGENT_API_KEY")
  )
  client <- codeagent_client(chat, permission_mode = "bypass")
  resp   <- codeagent(client, "In one sentence, what is R programming language?")
  cat(resp, "\n\n")
}

# Legacy style still works (backward-compatible)
cat("--- legacy style ---\n")
resp <- codeagent(
  "In one sentence, what is R programming language?",
  model           = Sys.getenv("CODEAGENT_MODEL", "gpt-4.1"),
  permission_mode = "bypass"
)
cat(resp, "\n\n")
