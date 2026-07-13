# Register the RunR tool to a Chat

Register the RunR tool to a Chat

## Usage

``` r
register_run_r_tool(
  chat,
  mode = "default",
  rules = list(),
  ask_fn = NULL,
  sandbox = NULL,
  async = FALSE
)
```

## Arguments

- chat:

  An [`ellmer::Chat`](https://ellmer.tidyverse.org/reference/Chat.html)
  object.

- mode:

  Character. Permission mode (see
  [PermissionMode](https://kaipingyang.github.io/codeagent/reference/PermissionMode.md)).

- rules:

  List.
  [`PermissionRule()`](https://kaipingyang.github.io/codeagent/reference/PermissionRule.md)
  objects.

- ask_fn:

  Function or NULL. `function(tool_name, input) -> logical`. Called when
  permission resolves to `"ask"`.

- sandbox:

  List or NULL. Sandbox profile (see
  [`.sandbox_profile()`](https://kaipingyang.github.io/codeagent/reference/dot-sandbox_profile.md)).
  RunR runs in-process so the environment cannot be scrubbed, but when
  the sandbox is enabled, code calling shell/process/env or (when
  network is disabled) network functions is refused.

## Value

Invisibly returns `chat`.
