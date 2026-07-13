# Create a codeagent.md configuration file

Copies the codeagent.md template to the project root (or
`.codeagent/config.md`).

## Usage

``` r
use_codeagent_md(path = "codeagent.md", open = interactive())
```

## Arguments

  - path:
    
    Character. Destination path. Defaults to `"codeagent.md"`.

  - open:
    
    Logical. Open the file after creation (requires rstudioapi).

## Value

Invisible character. Path to created file.
