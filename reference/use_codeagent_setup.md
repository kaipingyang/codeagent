# Interactive setup wizard for codeagent

Guides you through choosing a model provider, creates
`~/.codeagent/settings.json`, and optionally saves your API key to
`~/.Renviron`. Only works in interactive R sessions.

## Usage

``` r
use_codeagent_setup(scope = c("user", "project"))
```

## Arguments

- scope:

  Character. Must be `"user"` for provider setup. Project files cannot
  configure providers, endpoints, or credentials; pass an explicit Chat
  to
  [`codeagent_client()`](https://kaipingyang.github.io/codeagent/reference/codeagent_client.md)
  for project-specific backends.

## Value

Invisibly, the path to the settings file that was written.
