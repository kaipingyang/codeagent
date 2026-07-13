# Create the TeamRun tool

Exposes
[`team_run()`](https://kaipingyang.github.io/codeagent/reference/team_run.md)
to the model so it can fan out independent subtasks in parallel and get
all results back at once.

## Usage

``` r
team_run_tool(model = NULL, cwd = getwd())
```

## Arguments

- model:

  Character. Default model for team agents.

- cwd:

  Character. Working directory.

## Value

An [`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html)
object.
