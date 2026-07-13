# Check settings completeness and emit cli diagnostics

Verifies that the critical settings (backend URL and API key) are
present after all sources have been merged and `apiKeyHelper` has been
run. Emits `cli_alert_warning` + actionable hints for each gap. Intended
to run once at `codeagent_console()` startup so users see the problem
immediately rather than getting an opaque HTTP 401 on their first
message.

## Usage

``` r
.check_settings_completeness(settings)
```

## Arguments

  - settings:
    
    List from `load_settings()`.

## Value

Invisibly, a character vector of issue descriptions (empty = clean).
