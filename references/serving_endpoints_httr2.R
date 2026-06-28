library(httr2)

# Serving-endpoints batch test
# Auth: CODEAGENT_API_KEY (Databricks PAT)
# URL format: <base>/<model>/invocations
#
# Results (verified 2026-06-26):
#   OK (36):  databricks-claude-haiku-4-5, databricks-gpt-oss-*, databricks-llama-*,
#             databricks-meta-llama-*, databricks-gemma-*, databricks-qwen*,
#             gsds-DeepSeek-V4-*, deepseek-r1, deepseek-r1-distill-qwen-32b, deepseek-v3,
#             gsds-gpt-4o*, gsds-gpt41*, gsds-gpt-5*, gsds-gpt-51/52/54/55,
#             gsds-o1/o3/o3-mini/o4-mini, gsds-model-router, sp-gpt35t, sp-gpt4o
#   403 rate limit=0: databricks-claude-opus-* (5), databricks-claude-sonnet-* (3)
#   429 rate limited: deepseek-r1-distill-llama-70b
#   410 gone:         gsds-gpt45-preview
#   400:              gsds-openai-o1-mini

token <- Sys.getenv("CODEAGENT_API_KEY")
base  <- Sys.getenv("CODEAGENT_BASE_URL")  # https://adb-7234442748962802.2.azuredatabricks.net/serving-endpoints

models <- c(
  "databricks-claude-opus-4-8", "databricks-claude-opus-4-7", "databricks-claude-opus-4-6",
  "databricks-claude-opus-4-5", "databricks-claude-opus-4-1",
  "databricks-claude-sonnet-4-6", "databricks-claude-sonnet-4-5", "databricks-claude-sonnet-4",
  "databricks-claude-haiku-4-5",
  "databricks-gpt-oss-120b", "databricks-gpt-oss-20b",
  "databricks-llama-4-maverick", "databricks-meta-llama-3-3-70b-instruct",
  "databricks-meta-llama-3-1-8b-instruct", "databricks-gemma-3-12b",
  "databricks-qwen3-next-80b-a3b-instruct", "databricks-qwen35-122b-a10b",
  "gsds-DeepSeek-V4-Flash", "gsds-DeepSeek-V4-Pro",
  "deepseek-r1", "deepseek-r1-distill-llama-70b", "deepseek-r1-distill-qwen-32b", "deepseek-v3",
  "gsds-gpt-4o", "gsds-gpt-4o-mini",
  "gsds-gpt41", "gsds-gpt41-mini", "gsds-gpt41-nano", "gsds-gpt45-preview",
  "gsds-gpt-5", "gsds-gpt-5-chat", "gsds-gpt-5-mini", "gsds-gpt-5-nano",
  "gsds-gpt-51", "gsds-gpt-51-chat", "gsds-gpt-52", "gsds-gpt-54", "gsds-gpt-55",
  "gsds-o1", "gsds-openai-o1-mini", "gsds-o3", "gsds-o3-mini", "gsds-o4-mini",
  "gsds-model-router", "sp-gpt35t", "sp-gpt4o"
)

for (m in models) {
  resp <- tryCatch(
    request(paste0(base, "/", m, "/invocations")) |>
      req_headers(Authorization = paste("Bearer", token), "Content-Type" = "application/json") |>
      req_body_json(list(messages = list(list(role = "user", content = "hi")), max_tokens = 5L)) |>
      req_timeout(15) |>
      req_error(is_error = \(r) FALSE) |>
      req_perform(),
    error = function(e) NULL
  )
  if (is.null(resp)) { cat(sprintf("%-45s  timeout\n", m)); next }
  st   <- resp_status(resp)
  body <- tryCatch(resp_body_json(resp), error = \(e) list())
  note <- if (st == 200) "OK" else substr(body$message %||% "", 1, 50)
  cat(sprintf("%-45s  %d  %s\n", m, st, note))
}
