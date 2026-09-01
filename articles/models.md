# Models and providers

**Language:** English \|
[简体中文](https://kaipingyang.github.io/codeagent/articles/models-cn.md)

`codeagent` can wrap any configured
[`ellmer::Chat`](https://ellmer.tidyverse.org/reference/Chat.html).
Passing a Chat directly is the most general and least ambiguous provider
interface; the settings-based factory is a convenience for common
backends.

## Pass any ellmer Chat

``` r

chat <- ellmer::chat_openai_compatible(
  base_url = Sys.getenv("CODEAGENT_BASE_URL"),
  model = Sys.getenv("CODEAGENT_MODEL"),
  credentials = function() Sys.getenv("CODEAGENT_API_KEY"),
  preserve_thinking = TRUE
)

client <- codeagent_client(chat, permission_mode = "default")
```

Other examples use the provider’s native ellmer authentication:

``` r

anthropic_client <- codeagent_client(
  ellmer::chat_anthropic(model = "claude-sonnet-4-6")
)

ollama_client <- codeagent_client(
  ellmer::chat_ollama(model = "llama3.2")
)
```

When a Chat is supplied, codeagent replaces its system prompt with the
harness prompt and records its current model name. It otherwise
preserves the Chat’s provider configuration and model parameters.

## Automatic provider selection

With `chat = NULL`,
[`codeagent_client()`](https://kaipingyang.github.io/codeagent/reference/codeagent_client.md)
calls the internal settings factory. Selection is:

1.  an explicit `provider` setting, after removing an optional `chat_`
    prefix;
2.  `openai_compatible` when `base_url`/`CODEAGENT_BASE_URL` is present;
    or
3.  `anthropic` otherwise.

The current factory has branches for:

- `openai_compatible`, `openai`, `vllm`, and `lmstudio`;
- `anthropic` and its `claude` alias;
- `ollama`;
- `databricks`, `deepseek`, `google_gemini`, `google_vertex`, `groq`,
  and `github`;
- `aws_bedrock`, `azure_openai`, `mistral`, `perplexity`, `portkey`,
  `posit`, `huggingface`, `cloudflare`, `snowflake`, and `openrouter`.

Each value resolves to the corresponding `ellmer::chat_<provider>()`
function, which must exist in the installed ellmer version.
Authentication requirements are provider-specific. Factories that
receive an explicit credential closure use the environment variable
named by `api_key_env`, defaulting to `CODEAGENT_API_KEY`; Anthropic,
Bedrock, Vertex, Posit, and other native flows can rely on ellmer’s own
environment, IAM, or OAuth behavior.

For an OpenAI-compatible gateway:

``` json
{
  "provider": "openai_compatible",
  "model": "main",
  "env": {
    "CODEAGENT_BASE_URL": "https://YOUR-WORKSPACE/serving-endpoints",
    "CODEAGENT_MODEL": "your-main-endpoint"
  }
}
```

Keep the corresponding key outside JSON.

## Model specs and aliases

[`codeagent_client_config()`](https://kaipingyang.github.io/codeagent/reference/codeagent_client_config.md)
and
[`switch_model()`](https://kaipingyang.github.io/codeagent/reference/switch_model.md)
use the same smaller model-spec parser as their base. Its recognized
prefixes are:

| Spec | Constructor |
|----|----|
| `openai/<model>` | `chat_openai_compatible()` when `CODEAGENT_BASE_URL` is set |
| `anthropic/<model>` | `chat_anthropic()` |
| `ollama/<model>` | `chat_ollama()` |
| plain model name | automatic settings factory with that model |

Aliases are defined in `codeagent.md`:

``` yaml
---
client:
  main-gateway: openai/gpt-4.1
  direct-claude: anthropic/claude-sonnet-4-6
  local: ollama/llama3.2
---
Project instructions follow here.
```

``` r

client <- codeagent_client_config(alias = "main-gateway")
```

## Switch models without losing history

Always assign the result because a switch may return either the same
client or a rebuilt one:

``` r

client <- switch_model(client, "anthropic/claude-haiku-4-5")
```

[`switch_model()`](https://kaipingyang.github.io/codeagent/reference/switch_model.md)
first resolves the target into a fresh Chat and chooses one of two
verified routes:

- **Route A, name-only:** if provider configuration, credentials, model
  parameters, and API arguments are unchanged, `set_model()` changes
  only the name. The same Chat/client identity, tools, callbacks, and
  history remain.
- **Route B, rebuild:** provider, endpoint, credential, parameter, or
  API-argument changes build a new Chat/client. Turns, system prompt,
  tools, live settings, hooks, MCP configuration, budget, and the live
  Data Shield are carried forward. If rebuilding fails, the original
  client remains unchanged.

The CLI and direct R API accept both routes. Shiny modules capture Chat
identity, so the Settings model control and `/model` allow only verified
Route A switches and reject switches while a response is streaming. A
target requiring Route B must start a new Shiny session/app with the
desired configuration.

## Reasoning and thinking content

For an automatically built Chat, set the snake_case `effort_level`
field:

``` json
{
  "effort_level": "high"
}
```

When non-empty, it is passed as:

``` r

ellmer::params(reasoning_effort = "high")
```

Use a value supported by the selected model/provider, commonly `low`,
`medium`, `high`, or `xhigh`. codeagent does not validate the value
before passing it through. The camelCase field `effortLevel` is not
consumed by the automatic Chat factory. When passing an explicit Chat,
configure its `params` yourself:

``` r

chat <- ellmer::chat_openai_compatible(
  base_url = Sys.getenv("CODEAGENT_BASE_URL"),
  model = Sys.getenv("CODEAGENT_MODEL"),
  credentials = function() Sys.getenv("CODEAGENT_API_KEY"),
  params = ellmer::params(reasoning_effort = "high"),
  preserve_thinking = TRUE
)
```

The automatic `openai_compatible` branch sets
`preserve_thinking = TRUE`. Providers that expose reasoning as
[`ellmer::ContentThinking`](https://ellmer.tidyverse.org/reference/Content.html)
can stream it to the REPL’s dimmed thinking display and preserve it for
Shiny/session replay. This does not enable reasoning on a model that
does not support it.

## Main, heavy, and fast tiers

The tier map is built from:

| Tier | Variable | Automatic role |
|----|----|----|
| `main` | `CODEAGENT_MODEL` | Default active model and `main` alias. |
| `heavy` | `CODEAGENT_HEAVY_MODEL` | Alias only; codeagent does not automatically escalate hard tasks to it. |
| `fast` | `CODEAGENT_FAST_MODEL` | Preferred model for compaction, auto permission classification, memory relevance, and optional Data Shield review. |

``` ini
CODEAGENT_MODEL=your-main-endpoint
CODEAGENT_HEAVY_MODEL=your-heavy-endpoint
CODEAGENT_FAST_MODEL=your-fast-endpoint
```

Compaction prefers `CODEAGENT_FAST_MODEL`, then an option override, then
the active Chat’s model, and finally an internal Haiku fallback. The
`auto` permission mode similarly prefers the fast model and falls back
to the main model before its internal default. Configure a valid fast
endpoint when using a private OpenAI-compatible gateway.

## Context windows

The raw context window resolves in this order:

1.  positive `CODEAGENT_MAX_CONTEXT_TOKENS`;
2.  a `[1m]` suffix in the model name;
3.  a trusted provider-reported value or the built-in known-model table;
    and
4.  200,000 tokens.

The effective auto-compaction window reserves output space. A positive
`CODEAGENT_AUTO_COMPACT_WINDOW` can lower it, and any non-empty
`CODEAGENT_DISABLE_COMPACT` disables automatic threshold compaction.
Token counts use cached usage where available and otherwise estimate
locally; normal compaction/status paths do not make an implicit
token-count network request.

## Cost data and dollar budgets

A client can enforce a positive dollar cap:

``` r

client <- codeagent_client(max_budget_usd = 2.50)
```

The same setting is available as `max_budget_usd` in JSON or
`CODEAGENT_MAX_BUDGET_USD`. It relies on `chat$get_cost()`. If ellmer
has no price for a custom/private model, cost may remain zero and the
cap cannot fire.

Pricing data is never refreshed automatically during startup or model
requests. Refresh ellmer’s public snapshot explicitly when wanted:

``` r

price_update <- update_model_prices()
price_update$message
```

A failed refresh keeps the existing cache. Public-price refreshes may
still not add a match for a private endpoint.
