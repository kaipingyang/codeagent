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
    
    Character. `"user"` writes to `~/.codeagent/settings.json`;
    `"project"` writes to `.codeagent/settings.json` in the current
    directory.

## Value

Invisibly, the path to the settings file that was written.
