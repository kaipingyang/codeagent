# Build the codeagent system prompt

Assembles behavioural guidance (tone, doing-tasks, conventions, tool
use, R specifics) plus project context (CLAUDE.md, skills, permission
mode). Constant text only – ephemeral per-turn context lives in
[`.build_system_reminder()`](https://github.com/kaipingyang/codeagent/reference/dot-build_system_reminder.md).

## Usage

``` r
.build_system_prompt(settings, cwd = getwd())
```

## Arguments

- settings:

  List. Output of
  [`load_settings()`](https://github.com/kaipingyang/codeagent/reference/load_settings.md).

- cwd:

  Character. Working directory.

## Value

Character(1). The full system prompt.
