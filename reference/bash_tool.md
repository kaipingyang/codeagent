# Create the Bash tool

Create the Bash tool

## Usage

``` r
bash_tool(mode = "default", rules = list(), ask_fn = NULL, sandbox = NULL)
```

## Arguments

- mode:

  Character. Permission mode (see
  [PermissionMode](https://github.com/kaipingyang/codeagent/reference/PermissionMode.md)).

- rules:

  List.
  [`PermissionRule()`](https://github.com/kaipingyang/codeagent/reference/PermissionRule.md)
  objects.

- ask_fn:

  Function or NULL. `function(tool_name, input) -> logical`. Called when
  permission is `"ask"`.

- sandbox:

  List or NULL. Bash sandbox profile (see
  [`.sandbox_profile()`](https://github.com/kaipingyang/codeagent/reference/dot-sandbox_profile.md)):
  `list(enabled, allow_network, keep_env)`. When enabled, scrubs the
  command environment and can block network utilities.

## Value

An [`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html)
object.
