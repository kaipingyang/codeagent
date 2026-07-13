# Resolve a model spec/alias into a fresh ellmer Chat

Thin wrapper over `.parse_client_spec()` so model switching reuses the
same alias + provider-prefix resolution as `codeagent_client_config()`.

## Usage

``` r
.resolve_model_chat(model, cwd = getwd())
```

## Arguments

  - model:
    
    Character. `"anthropic/..."`, `"openai/..."`, `"ollama/..."`, a
    plain model name, or an alias defined in `codeagent.md`.

  - cwd:
    
    Character. Working directory (for alias lookup).

## Value

A fresh `ellmer::Chat`.
