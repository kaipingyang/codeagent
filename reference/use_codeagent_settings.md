# Create a codeagent settings.json file

Copies the package template to `~/.codeagent/settings.json` (user scope)
or `.codeagent/settings.json` (project scope). The template uses
placeholder values – edit it to add real endpoint names and tier
mappings. Store your API key in `.Renviron` as `CODEAGENT_API_KEY`,
never in settings.json.

## Usage

``` r
use_codeagent_settings(scope = c("user", "project"), open = interactive())
```

## Arguments

  - scope:
    
    Character. `"user"` (default) writes to `~/.codeagent/`; `"project"`
    writes to `.codeagent/` in the current directory.

  - open:
    
    Logical. Open the file after creation when running in RStudio/
    Positron (requires rstudioapi).

## Value

Invisible character. Path to created file.
