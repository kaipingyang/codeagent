# Resolve a model spec/alias into a fresh ellmer Chat

Thin wrapper over
[`.parse_client_spec()`](https://kaipingyang.github.io/codeagent/reference/dot-parse_client_spec.md)
so model switching reuses the same alias + provider-prefix resolution as
[`codeagent_client_config()`](https://kaipingyang.github.io/codeagent/reference/codeagent_client_config.md).

## Usage

``` r
.resolve_model_chat(
  model,
  cwd = getwd(),
  setting_sources = c("user", "project")
)
```

## Arguments

- model:

  Character. `"anthropic/..."`, `"openai/..."`, `"ollama/..."`, a plain
  model name, or an alias defined in `codeagent.md`.

- cwd:

  Character. Working directory (for alias lookup).

- setting_sources:

  Passed to
  [`load_settings()`](https://kaipingyang.github.io/codeagent/reference/load_settings.md)
  for a plain model name, so a client built with
  `setting_sources = "project"` keeps ignoring the user-level settings
  when the model is switched.

## Value

A fresh
[`ellmer::Chat`](https://ellmer.tidyverse.org/reference/Chat.html).
