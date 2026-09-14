# Check whether a tool call is permitted

Evaluates the permission decision for a single tool call, applying all
relevant rules in priority order.

## Usage

``` r
check_permission(
  tool_name,
  mode = "default",
  rules = list(),
  tool_input = NULL,
  allow_plan_exit = FALSE
)
```

## Arguments

- tool_name:

  Character(1). Name of the tool (e.g. `"Bash"`, `"Write"`).

- mode:

  Character(1). One of the values in
  [PermissionMode](https://kaipingyang.github.io/codeagent/reference/PermissionMode.md).

- rules:

  List of
  [`PermissionRule()`](https://kaipingyang.github.io/codeagent/reference/PermissionRule.md)
  objects. Every matching explicit deny is absolute; declaration order
  is preserved only among remaining allow/ask rules.

- tool_input:

  List or NULL. Tool arguments (used for Bash read-only detection).

- allow_plan_exit:

  Logical. Whether `ExitPlanMode` may restore a mode after a trusted
  in-session `EnterPlanMode` transition.

## Value

Character(1): `"allow"`, `"deny"`, or `"ask"`.
