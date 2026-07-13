# Register all built-in codeagent tools to a Chat

Register all built-in codeagent tools to a Chat

## Usage

``` r
register_builtin_tools(
  chat,
  mode = "default",
  rules = list(),
  ask_fn = NULL,
  skip_file_tools = FALSE,
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
  permission is `"ask"`.

- skip_file_tools:

  Logical. If `TRUE`, skip Read/Write/Edit/MultiEdit/Glob/Grep/LS and
  register only Bash. Advanced use: set this if you want btw file tools
  to be the *only* file tools (no absolute-path fallback). Default
  `FALSE` means both codeagent and btw file tools coexist when Path A is
  enabled.

- sandbox:

  List or NULL. Bash sandbox profile (see
  [`.sandbox_profile()`](https://kaipingyang.github.io/codeagent/reference/dot-sandbox_profile.md));
  passed through to
  [`bash_tool()`](https://kaipingyang.github.io/codeagent/reference/bash_tool.md).

- async:

  Logical. If `TRUE`, register async permission-gated tool variants for
  the Shiny path (UI-gated approvals). Default `FALSE` (synchronous).

## Value

Invisibly returns `chat`.
