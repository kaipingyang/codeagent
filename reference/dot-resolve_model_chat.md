# Resolve a model spec/alias into a fresh ellmer Chat

Thin wrapper over
[`.parse_client_spec()`](https://github.com/kaipingyang/codeagent/reference/dot-parse_client_spec.md)
so model switching reuses the same alias + provider-prefix resolution as
[`codeagent_client_config()`](https://github.com/kaipingyang/codeagent/reference/codeagent_client_config.md).

## Usage

``` r
.resolve_model_chat(model, cwd = getwd())
```

## Arguments

- model:

  Character. `"anthropic/..."`, `"openai/..."`, `"ollama/..."`, a plain
  model name, or an alias defined in `codeagent.md`.

- cwd:

  Character. Working directory (for alias lookup).

## Value

A fresh
[`ellmer::Chat`](https://ellmer.tidyverse.org/reference/Chat.html).
