# Declare a host tool's permission capability

Register the permission **capability** of a tool that a host application
attaches to the chat (via `chat$register_tool()`), so codeagent's
central permission gate governs it like a native tool.

codeagent classifies every tool call by capability. Built-in tools are
known; any **unregistered** tool defaults to `"read"` and is therefore
allowed **without gating**. If a host tool performs sensitive actions
(writing files, executing code, network access), declare it here so the
gate can `ask`/`deny` it under the active permission mode and
`settings$tools` policy.

Built-in tool metadata stays authoritative – this only classifies tools
not already known to codeagent. Registrations persist for the R session.

## Usage

``` r
register_tool_meta(
  name,
  capability = c("read", "write", "exec", "net"),
  set = "C"
)
```

## Arguments

- name:

  Character(1). Tool name (must match the
  [`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html)
  name).

- capability:

  One of `"read"`, `"write"`, `"exec"`, `"net"`. Use `"read"` for
  read-only/benign tools (allowed without prompting);
  `"write"`/`"exec"`/ `"net"` route through the permission gate.

- set:

  Character(1). Optional grouping label for reporting (default `"C"` =
  host/custom). Not used in gate decisions.

## Value

Invisibly, `name`.

## See also

[`codeagent_client()`](https://kaipingyang.github.io/codeagent/reference/codeagent_client.md),
[`register_builtin_tools()`](https://kaipingyang.github.io/codeagent/reference/register_builtin_tools.md)

## Examples

``` r
if (FALSE) { # \dontrun{
chat$register_tool(my_run_code_tool)      # a host tool that executes R code
register_tool_meta("RunTFLCode", "exec")  # -> gated like Bash / RunR
} # }
```
