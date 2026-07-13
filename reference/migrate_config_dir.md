# Migrate the codeagent config directory to the OS-standard location

Copies a legacy `~/.codeagent` directory into the platform config
directory (`rappdirs::user_config_dir("codeagent")`). Idempotent and
safe to call repeatedly; normally runs automatically on first use.

## Usage

``` r
migrate_config_dir(quiet = FALSE)
```

## Arguments

  - quiet:
    
    Logical. Suppress the migration message.

## Value

Invisibly `TRUE` if a migration happened, else `FALSE`.
