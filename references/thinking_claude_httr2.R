library(httr2)

# Claude Haiku 4.5 via Databricks: thinking content via raw httr2
#
# Use when ellmer patch is not desired. Non-streaming only.
# max_tokens must exceed budget_tokens (minimum 1024).

base_url <- Sys.getenv("CODEAGENT_BASE_URL")
api_key  <- Sys.getenv("CODEAGENT_API_KEY")

resp <- request(paste0(base_url, "/databricks-claude-haiku-4-5/invocations")) |>
  req_headers(
    Authorization  = paste("Bearer", api_key),
    "Content-Type" = "application/json"
  ) |>
  req_body_json(list(
    messages   = list(list(role = "user", content = "What is 17 * 23?")),
    max_tokens = 2000L,
    thinking   = list(type = "enabled", budget_tokens = 1024L)
  )) |>
  req_perform()

body     <- resp_body_json(resp)
contents <- body$choices[[1]]$message$content

for (block in contents) {
  if (block$type == "reasoning") {
    cat("=== THINKING ===\n")
    cat(block$summary[[1]]$text, "\n\n")
  } else if (block$type == "text") {
    cat("=== ANSWER ===\n")
    cat(block$text, "\n")
  }
}
