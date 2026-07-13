# Models and providers

codeagent wraps any `ellmer` Chat, so it is provider-agnostic.

## Any ellmer backend

``` r

chat <- ellmer::chat_openai_compatible(   # Databricks / Azure / vLLM / custom
  base_url    = Sys.getenv("CODEAGENT_BASE_URL"),
  model       = Sys.getenv("CODEAGENT_MODEL"),
  credentials = function() Sys.getenv("CODEAGENT_API_KEY")
)
client <- codeagent_client(chat, permission_mode = "bypass")
```

Supported `provider` values include `openai_compatible`, `anthropic`,
`openai`, `google_gemini`, `deepseek`, `groq`, `github`, `ollama`,
`posit`, `databricks`, `aws_bedrock`, and `azure_openai`.

## Switching models mid-session

``` r

switch_model(client, "openai/deepseek-r1")   # CLI / one-shot
# In the Shiny app: the Settings panel model picker, or /model
```

The Shiny path swaps the provider in place (Route A) so the `Chat`
object identity — and every callback/closure bound to it — stays valid.

## Reasoning / thinking

Models with extended thinking are controlled natively via ellmer:

``` r

# settings.json: "effortLevel": "high"  ->  params(reasoning_effort = "high")
```

For OpenAI-compatible endpoints (Databricks Claude, DeepSeek), codeagent
sets `preserve_thinking = TRUE`, so `reasoning_content` is parsed into
ellmer `ContentThinking` and rendered distinctly (dimmed in the REPL, a
collapsible block in the Shiny UI).

## Small/fast model

Compaction and permission classification use a cheaper model. Set it via
`CODEAGENT_FAST_MODEL` (the `"fast"` tier).
