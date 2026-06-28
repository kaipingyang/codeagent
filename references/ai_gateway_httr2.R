library(httr2)

# AI Gateway endpoint
# Base URL: ai-gateway.azuredatabricks.net/mlflow/v1
# Auth: CODEAGENT_API_KEY (same Databricks PAT as serving-endpoints)
#
# IMPORTANT: ai-gateway requires lowercase model names.
#   gsds-DeepSeek-V4-Pro → use gsds-deepseek-v4-pro (lowercase)
#   gsds-DeepSeek-V4-Flash → use gsds-deepseek-v4-flash (lowercase)
#
# Available models on this gateway (verified 2026-06-26):
#   gsds-deepseek-v4-pro    OK  (lowercase alias of gsds-DeepSeek-V4-Pro)
#   gsds-deepseek-v4-flash  OK  (lowercase alias of gsds-DeepSeek-V4-Flash)
#   gsds-gpt-54             OK
#   gsds-gpt-55             OK
#   databricks-*            403 (rate limit = 0, IT restricted)
#   deepseek-r1 / gsds-gpt41 / gsds-o* etc.  404 (not on this gateway)
#
# Use serving-endpoints for full model coverage.

token <- Sys.getenv("CODEAGENT_API_KEY")
base  <- "https://7234442748962802.2.ai-gateway.azuredatabricks.net/mlflow/v1/chat/completions"

# ---------------------------------------------------------------------------
# Single model example
# ---------------------------------------------------------------------------

resp <- request(base) |>
  req_headers(
    Authorization  = paste("Bearer", token),
    "Content-Type" = "application/json"
  ) |>
  req_body_json(list(
    model      = "gsds-deepseek-v4-pro",
    messages   = list(list(role = "user", content = "What is an LLM agent?")),
    max_tokens = 500L
  )) |>
  req_perform()

body <- resp_body_json(resp)
cat(body$choices[[1]]$message$content)

# ---------------------------------------------------------------------------
# Batch test: all chat models from databricks_model_list
# Note: use lowercase names — gateway requires lowercase (serving-endpoints is case-insensitive)
# ---------------------------------------------------------------------------

models <- c(
  "databricks-claude-opus-4-8", "databricks-claude-opus-4-7", "databricks-claude-opus-4-6",
  "databricks-claude-opus-4-5", "databricks-claude-opus-4-1",
  "databricks-claude-sonnet-4-6", "databricks-claude-sonnet-4-5", "databricks-claude-sonnet-4",
  "databricks-claude-haiku-4-5",
  "databricks-gpt-oss-120b", "databricks-gpt-oss-20b",
  "databricks-llama-4-maverick", "databricks-meta-llama-3-3-70b-instruct",
  "databricks-meta-llama-3-1-8b-instruct", "databricks-gemma-3-12b",
  "databricks-qwen3-next-80b-a3b-instruct", "databricks-qwen35-122b-a10b",
  "gsds-deepseek-v4-flash", "gsds-deepseek-v4-pro",
  "deepseek-r1", "deepseek-r1-distill-llama-70b", "deepseek-r1-distill-qwen-32b",
  "deepseek-v3",
  "gsds-gpt-4o", "gsds-gpt-4o-mini",
  "gsds-gpt41", "gsds-gpt41-mini", "gsds-gpt41-nano",
  "gsds-gpt45-preview",
  "gsds-gpt-5", "gsds-gpt-5-chat", "gsds-gpt-5-mini", "gsds-gpt-5-nano",
  "gsds-gpt-51", "gsds-gpt-51-chat", "gsds-gpt-52", "gsds-gpt-54", "gsds-gpt-55",
  "gsds-o1", "gsds-openai-o1-mini", "gsds-o3", "gsds-o3-mini", "gsds-o4-mini",
  "gsds-model-router",
  "sp-gpt35t", "sp-gpt4o"
)

for (m in models) {
  resp <- tryCatch(
    request(base) |>
      req_headers(Authorization = paste("Bearer", token), "Content-Type" = "application/json") |>
      req_body_json(list(model = m, messages = list(list(role = "user", content = "hi")), max_tokens = 5L)) |>
      req_timeout(15) |>
      req_error(is_error = \(r) FALSE) |>
      req_perform(),
    error = function(e) NULL
  )
  if (is.null(resp)) { cat(sprintf("%-45s  timeout\n", m)); next }
  st   <- resp_status(resp)
  body <- tryCatch(resp_body_json(resp), error = \(e) list())
  note <- if (st == 200) "OK" else substr(body$message %||% "", 1, 55)
  cat(sprintf("%-45s  %d  %s\n", m, st, note))
}
