# Build the codeagent system prompt

Assembles behavioural guidance (tone, doing-tasks, conventions, tool
use, R specifics) plus project context (CLAUDE.md, skills, permission
mode). Constant text only – ephemeral per-turn context lives in
`.build_system_reminder()`.

## Usage

``` r
.build_system_prompt(settings, cwd = getwd())
```

## Arguments

  - settings:
    
    List. Output of `load_settings()`.

  - cwd:
    
    Character. Working directory.

## Value

Character(1). The full system prompt.
