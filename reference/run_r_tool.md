# Create the RunR tool

Runs R code in the current session and captures return values, printed
output, messages, warnings, errors, and plots. Because arbitrary R
execution can read/write files, hit the network, or mutate global state,
the call is gated through `check_permission()` under the tool name
`"RunR"`.

## Usage

``` r
run_r_tool(mode = "default", rules = list(), ask_fn = NULL, sandbox = NULL)
```

## Arguments

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

An `ellmer::tool()` object, or `NULL` if btw is unavailable.
