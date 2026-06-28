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

models <- c("gsds-gpt41", "gsds-gpt-54", "gsds-gpt-55")

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
cat("--- gsds-gpt41 (legacy style) ---\n")
resp <- codeagent(
  "In one sentence, what is R programming language?",
  model           = "gsds-gpt41",
  permission_mode = "bypass"
)
cat(resp, "\n\n")
