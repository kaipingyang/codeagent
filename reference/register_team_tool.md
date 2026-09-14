# Register the TeamRun tool on a chat

Register the TeamRun tool on a chat

## Usage

``` r
register_team_tool(
  chat,
  model = NULL,
  cwd = getwd(),
  parent_rules = NULL,
  parent_policy = NULL,
  security_context = NULL
)
```

## Arguments

- chat:

  An [`ellmer::Chat`](https://ellmer.tidyverse.org/reference/Chat.html)
  object.

- model:

  Character. Default model for team agents.

- cwd:

  Character. Working directory.

- parent_rules:

  List. Permission rules inherited from parent.

- parent_policy:

  List. Tool capability policies inherited from parent.

- security_context:

  Internal immutable parent security snapshot.

## Value

Invisibly `chat`.
