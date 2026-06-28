#!/usr/bin/env Rscript
# inst/examples/demo_04_thinking.R
#
# Demo: visible thinking content via deepseek-r1 (ContentThinking)
# Run from package root: Rscript inst/examples/demo_04_thinking.R

library(ellmer)

# Merge adjacent same-type ContentThinking / ContentText blocks
merge_thinking_content <- function(contents) {
  if (length(contents) == 0) return(list())
  acc <- list(contents[[1]])
  for (i in seq_along(contents)[-1]) {
    item <- contents[[i]]
    n    <- length(acc)
    prev <- acc[[n]]
    if (S7::S7_inherits(prev, ContentThinking) && S7::S7_inherits(item, ContentThinking)) {
      acc[[n]] <- ContentThinking(paste0(prev@thinking, item@thinking))
    } else if (S7::S7_inherits(prev, ContentText) && S7::S7_inherits(item, ContentText)) {
      acc[[n]] <- ContentText(paste0(prev@text, item@text))
    } else {
      acc <- c(acc, list(item))
    }
  }
  acc
}

cat("=== Demo 4: Thinking Content (deepseek-r1) ===\n\n")

chat <- chat_openai_compatible(
  base_url          = Sys.getenv("CODEAGENT_BASE_URL"),
  model             = "deepseek-r1",
  credentials       = function() Sys.getenv("CODEAGENT_API_KEY"),
  preserve_thinking = TRUE,
  echo              = "none"
)

prompts <- c(
  "What is 17 * 23?",
  "Is 97 a prime number?"
)

for (prompt in prompts) {
  cat(sprintf("--- Question: %s ---\n", prompt))
  chat$chat(prompt)

  merged <- merge_thinking_content(chat$last_turn("assistant")@contents)

  for (content in merged) {
    if (S7::S7_inherits(content, ContentThinking)) {
      cat("[ THINKING ]\n")
      cat(content@thinking, "\n\n")
    } else if (S7::S7_inherits(content, ContentText)) {
      cat("[ ANSWER ]\n")
      cat(content@text, "\n\n")
    }
  }
}
