# Pre-process a chat input to detect slash commands

Detects `/skillname [args]` patterns.

## Usage

``` r
.preprocess_input(input, cwd = getwd())
```

## Arguments

  - input:
    
    Character(1). Raw user input.

  - cwd:
    
    Character. Working directory.

## Value

Named list:

  - `type = "normal"`: plain text, send to LLM.

  - `type = "command"`: built-in local command (not sent to LLM).

  - `type = "skill"`: skill invocation (load prompt, then send to LLM).
