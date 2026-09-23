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
  allow_plan_exit = FALSE,
  capability = NULL
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

- capability:

  Optional character(1). The caller's resolved capability for this tool
  (`"read"`, `"write"`, `"exec"`, `"net"`). The central gate passes what
  it resolved from the live `ToolDef`, which can see annotations a
  name-only lookup cannot (btw sets `read_only_hint` on every tool it
  ships). Ignored for tools listed in the built-in metadata, so a host
  cannot downgrade `Bash` by passing `"read"`. `NULL` resolves from the
  tool name.

## Value

Character(1): `"allow"`, `"deny"`, or `"ask"`.
