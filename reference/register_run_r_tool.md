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
  Enabling sandboxing fails closed unless `run_r_backend = "process"` is
  explicitly selected. That fallback uses a separate `callr` process
  with a timeout and best-effort environment hygiene, but is not an OS
  security boundary and does not restrict filesystem, network, or
  process access.

## Value

Invisibly returns `chat`.
