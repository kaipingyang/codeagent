# Create the TeamRun tool

Exposes
[`team_run()`](https://kaipingyang.github.io/codeagent/reference/team_run.md)
to the model so it can fan out independent subtasks in parallel and get
all results back at once.

## Usage

``` r
team_run_tool(
  model = NULL,
  cwd = getwd(),
  parent_rules = NULL,
  parent_policy = NULL,
  security_context = NULL
)
```

## Arguments

- model:

  Character. Default model for team agents.

- cwd:

  Character. Working directory.

- parent_rules:

  List. Permission rules inherited from the parent.

- parent_policy:

  List. Tool capability policies inherited from parent.

- security_context:

  Internal immutable parent security snapshot.

## Value

An [`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html)
object.
