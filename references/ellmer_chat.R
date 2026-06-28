library(ellmer)
library(httr2)

# OpenAI-compatible endpoint (e.g. Azure Databricks serving endpoint)
# CODEAGENT_BASE_URL="https://adb-7234442748962802.2.azuredatabricks.net/serving-endpoints"
# CODEAGENT_MODEL="gsds-gpt41"

# Example 1: basic chat
chat <- chat_openai_compatible(
  base_url    = Sys.getenv("CODEAGENT_BASE_URL"),
  model       = Sys.getenv("CODEAGENT_MODEL"),
  credentials = function() Sys.getenv("CODEAGENT_API_KEY")
)

chat$chat("test")

# Example 2: specify model directly
chat <- chat_openai_compatible(
  base_url    = Sys.getenv("CODEAGENT_BASE_URL"),
  model       = "gsds-gpt-54",
  credentials = function() Sys.getenv("CODEAGENT_API_KEY")
)

chat$chat("test")

# Example 3: reasoning_effort for GPT models
#
# params(reasoning_effort = "high") is silently ignored — ProviderOpenAICompatible
# whitelist excludes it. Pass via api_args instead (merged into request body directly).
# GPT-4.x/5.x accept the field but do NOT return thinking text; reasoning happens
# server-side only. reasoning_tokens count visible in usage.
chat <- chat_openai_compatible(
  base_url    = Sys.getenv("CODEAGENT_BASE_URL"),
  model       = "gsds-gpt-54",
  credentials = function() Sys.getenv("CODEAGENT_API_KEY"),
  api_args    = list(reasoning_effort = "high")
)

chat$chat("What is 17 * 23?")
chat$tokens()  # shows reasoning_tokens count in completion_tokens_details

# Example 4: visible thinking content via DeepSeek R1
#
# deepseek-r1 returns reasoning_content; ellmer parses it as ContentThinking natively.
# preserve_thinking = TRUE keeps thinking blocks in history for multi-turn.
chat <- chat_openai_compatible(
  base_url          = Sys.getenv("CODEAGENT_BASE_URL"),
  model             = "deepseek-r1",
  credentials       = function() Sys.getenv("CODEAGENT_API_KEY"),
  preserve_thinking = TRUE
)

chat$chat("What is 17 * 23?")

last <- chat$last_turn("assistant")
for (content in last@contents) {
  if (S7::S7_inherits(content, ContentThinking)) {
    cat("=== THINKING ===\n", content@thinking, "\n")
  } else if (S7::S7_inherits(content, ContentText)) {
    cat("=== ANSWER ===\n", content@text, "\n")
  }
}

# Example 5: Claude extended thinking via databricks-claude-haiku-4-5
#
# ellmer's ProviderOpenAICompatible stream_content and value_turn only handle
# delta.reasoning_content (DeepSeek format). Claude-through-Databricks returns
# delta.content as a typed-block array: [{type:"reasoning", summary:[...]}, {type:"text",...}].
# Two S7 methods must be patched to handle this format.
#
# Constraints:
#   - Only databricks-claude-haiku-4-5 has non-zero rate limit (Sonnet/Opus → 403)
#   - max_tokens must be > budget_tokens (minimum 1024)
#   - patch survives per-session; re-apply after library() in new sessions


chat <- chat_openai_compatible(
  base_url          = Sys.getenv("CODEAGENT_BASE_URL"),
  model             = "databricks-claude-haiku-4-5",
  credentials       = function() Sys.getenv("CODEAGENT_API_KEY"),
  preserve_thinking = TRUE
)

chat$chat("What is 17 * 23?")

# HTTP 403 Forbidden
chat <- chat_openai_compatible(
  base_url          = Sys.getenv("CODEAGENT_BASE_URL"),
  model             = "databricks-claude-sonnet-4-6",
  credentials       = function() Sys.getenv("CODEAGENT_API_KEY"),
  preserve_thinking = TRUE
)

chat$chat("What is 17 * 23?")

patch_ellmer_for_databricks_claude <- function() {
  ns <- getNamespace("ellmer")
  unlockBinding("stream_content", ns)
  unlockBinding("value_turn", ns)

  # Patch stream_content: handle delta.content as typed-block list (Claude format)
  # alongside existing delta.reasoning_content string support (DeepSeek format)
  S7::method(ns$stream_content, ns$ProviderOpenAICompatible) <- function(provider, event) {
    if (length(event$choices) == 0) return(NULL)
    delta <- event$choices[[1]]$delta

    reasoning <- delta[["reasoning_content"]]
    if (!is.null(reasoning)) return(ns$ContentThinking(reasoning))

    content <- delta[["content"]]
    if (is.null(content)) return(NULL)

    if (is.list(content)) {
      for (block in content) {
        if (identical(block$type, "reasoning")) {
          text <- block$summary[[1]]$text
          if (!is.null(text) && nchar(text) > 0) return(ns$ContentThinking(text))
        } else if (identical(block$type, "text")) {
          if (!is.null(block$text) && nchar(block$text) > 0) return(ns$ContentText(block$text))
        }
      }
      return(NULL)
    }

    ns$ContentText(content)
  }

  # Patch value_turn: handle message.content as typed-block list (non-streaming path)
  S7::method(ns$value_turn, ns$ProviderOpenAICompatible) <- function(provider, result, has_type = FALSE) {
    choice <- result$choices[[1]]
    msg <- if ("delta" %in% names(choice)) choice$delta else choice$message

    thinking <- list()
    reasoning <- msg$reasoning_content
    if (is.character(reasoning) && length(reasoning) == 1 && nzchar(reasoning))
      thinking <- list(ns$ContentThinking(reasoning))

    if (has_type) {
      content <- if (is.character(msg$content)) list(ns$ContentJson(string = msg$content[[1]]))
                 else list(ns$ContentJson(data = msg$content))
    } else {
      raw <- msg$content
      if (is.null(raw) || (is.character(raw) && !nzchar(raw))) {
        content <- list()
      } else if (is.list(raw)) {
        content <- list()
        for (block in raw) {
          if (is.list(block) && !is.null(block$type)) {
            if (identical(block$type, "reasoning")) {
              text <- block$summary[[1]]$text
              if (!is.null(text) && nchar(text) > 0)
                thinking <- c(thinking, list(ns$ContentThinking(text)))
            } else if (identical(block$type, "text")) {
              if (!is.null(block$text)) content <- c(content, list(ns$ContentText(block$text)))
            }
          } else {
            content <- c(content, list(ns$as_content(block)))
          }
        }
      } else {
        content <- list(ns$ContentText(as.character(raw)))
      }
    }

    if ("tool_calls" %in% names(msg)) {
      calls <- lapply(msg$tool_calls, function(call) {
        name <- call$`function`$name
        args <- tryCatch(jsonlite::parse_json(call$`function`$arguments), error = function(e) list())
        ns$ContentToolRequest(name = name, arguments = args, id = call$id)
      })
      content <- c(content, calls)
    }

    content <- c(thinking, content)
    tokens <- ns$value_tokens(provider, result)
    cost   <- ns$get_token_cost(provider, tokens)
    ns$AssistantTurn(content, json = result, tokens = unlist(tokens), cost = cost)
  }

  invisible(NULL)
}

# merge_content_text inside ellmer's coro closure cannot be patched (captured by ref).
# Post-process: merge adjacent same-type thinking/text blocks into one.
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

patch_ellmer_for_databricks_claude()

chat <- chat_openai_compatible(
  base_url          = Sys.getenv("CODEAGENT_BASE_URL"),
  model             = "databricks-claude-haiku-4-5",
  credentials       = function() Sys.getenv("CODEAGENT_API_KEY"),
  preserve_thinking = TRUE,
  api_args          = list(
    thinking   = list(type = "enabled", budget_tokens = 1024L),
    max_tokens = 2000L
  )
)

chat$chat("What is 17 * 23?")

merged <- merge_thinking_content(chat$last_turn("assistant")@contents)
for (content in merged) {
  if (S7::S7_inherits(content, ContentThinking)) cat("=== THINKING ===\n", content@thinking, "\n\n")
  if (S7::S7_inherits(content, ContentText))    cat("=== ANSWER ===\n",   content@text,    "\n")
}
