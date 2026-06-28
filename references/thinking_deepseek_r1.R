library(ellmer)

# DeepSeek R1: thinking content via chat_openai_compatible
# reasoning_content field natively parsed as ContentThinking — no patch needed

chat <- chat_openai_compatible(
  base_url          = Sys.getenv("CODEAGENT_BASE_URL"),
  model             = "deepseek-r1",
  credentials       = function() Sys.getenv("CODEAGENT_API_KEY"),
  preserve_thinking = TRUE
)

chat$chat("What is 17 * 23?")

last <- chat$last_turn("assistant")
for (content in last@contents) {
  if (S7::S7_inherits(content, ContentThinking)) cat("=== THINKING ===\n", content@thinking, "\n\n")
  if (S7::S7_inherits(content, ContentText))    cat("=== ANSWER ===\n",   content@text,    "\n")
}


chat <- chat_openai_compatible(
  base_url          = Sys.getenv("CODEAGENT_BASE_URL"),
  model             = "deepseek-r1",
  credentials       = function() Sys.getenv("CODEAGENT_API_KEY"),
  preserve_thinking = TRUE
)

chat$chat("What is 17 * 23?")