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
    
    An `ellmer::Chat` object.

  - mode:
    
    Character. Permission mode (see
    [PermissionMode](https://kaipingyang.github.io/codeagent/reference/PermissionMode.md)).

  - rules:
    
    List. `PermissionRule()` objects.

  - ask\_fn:
    
    Function or NULL. `function(tool_name, input) -> logical`. Called
    when permission resolves to `"ask"`.

  - sandbox:
    
    List or NULL. Sandbox profile (see `.sandbox_profile()`). RunR runs
    in-process so the environment cannot be scrubbed, but when the
    sandbox is enabled, code calling shell/process/env or (when network
    is disabled) network functions is refused.

## Value

Invisibly returns `chat`.
