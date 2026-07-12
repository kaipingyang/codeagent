#!/usr/bin/env Rscript
# inst/examples/demo_02_multi_turn.R
#
# Demo: multi-turn conversation via agent_loop()
# Run from package root: Rscript inst/examples/demo_02_multi_turn.R

devtools::load_all(quiet = TRUE)

cat("=== Demo 2: Multi-turn Conversation ===\n\n")

# New style: create client once, pass to agent_loop each turn
chat <- ellmer::chat_openai_compatible(
  base_url    = Sys.getenv("CODEAGENT_BASE_URL"),
  model       = "gpt-4.1",
  credentials = function() Sys.getenv("CODEAGENT_API_KEY")
)
client <- codeagent_client(chat, permission_mode = "bypass", max_turns = 10L)

turns <- list(
  "My name is Kaiping. Remember it.",
  "What is 17 * 23? Show your work.",
  "What is my name?"
)

for (i in seq_along(turns)) {
  cat(sprintf("--- Turn %d ---\n", i))
  cat(sprintf("User: %s\n", turns[[i]]))
  result <- agent_loop(turns[[i]], client, iteration = i)
  cat(sprintf("Assistant: %s\n", result$response))
  cat(sprintf("Stop reason: %s\n\n", result$stop_reason))
}
