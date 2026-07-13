# Build a system-reminder block for dynamic per-turn context injection

Mirrors Claude Code's `<system-reminder>` pattern: ephemeral context
appended to the user message (not the system prompt) to preserve
caching.

## Usage

``` r
.build_system_reminder(settings, iteration = 1L, cwd = getwd(), query = NULL)
```

## Arguments

  - settings:
    
    List. Output of `load_settings()`.

  - iteration:
    
    Integer. Current agent loop iteration.

  - cwd:
    
    Character. Working directory.

  - query:
    
    Character or NULL. Current user input for memory relevance.

## Value

Character(1). The reminder block, or `""` if nothing to inject.
