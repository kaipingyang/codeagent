# Install codeagent's central permission gate on an existing Chat

For hosts that build a harness-only client
(`codeagent_client(register_tools = FALSE)`) and attach their own domain
tools, then want those tools governed by codeagent's central permission
gate.

Declare each sensitive tool's capability with
[`register_tool_meta()`](https://kaipingyang.github.io/codeagent/reference/register_tool_meta.md)
(or pass `tool_meta` here), then call this once after attaching the
tools. Tools whose capability resolves to `"read"` are allowed without
gating; `write`/`exec`/ `net` route through the gate under
`permission_mode` + the `tools` policy.

Idempotent per chat: calling again refreshes the live mode / ask_fn /
policy rather than stacking a second gate.

## Usage

``` r
install_permission_gate(
  chat,
  permission_mode = "default",
  rules = list(),
  tools = list(),
  ask_fn = NULL,
  tool_meta = list()
)
```

## Arguments

- chat:

  An [`ellmer::Chat`](https://ellmer.tidyverse.org/reference/Chat.html).

- permission_mode:

  Character. One of the 7 modes (default `"default"`).

- rules:

  List. Fine-grained permission rules (see
  [`check_permission()`](https://kaipingyang.github.io/codeagent/reference/check_permission.md)).

- tools:

  List. `settings$tools` policy (`sets` / `capabilities` / `overrides`).

- ask_fn:

  Function or NULL. Permission callback invoked when a tool needs
  approval; may return a logical or a promise (async / Shiny). Called as
  `ask_fn(name, input)`, or `ask_fn(name, input, id = <tool_call_id>)`
  if it declares an `id` argument or `...`.

- tool_meta:

  Named list mapping tool name -\> capability
  (`"read"`/`"write"`/`"exec"`/`"net"`), a convenience for calling
  [`register_tool_meta()`](https://kaipingyang.github.io/codeagent/reference/register_tool_meta.md)
  on each before installing the gate.

## Value

Invisibly, `chat`.

## See also

[`register_tool_meta()`](https://kaipingyang.github.io/codeagent/reference/register_tool_meta.md),
[`codeagent_client()`](https://kaipingyang.github.io/codeagent/reference/codeagent_client.md)

## Examples

``` r
if (FALSE) { # \dontrun{
client <- codeagent_client(chat, register_tools = FALSE)
chat$register_tool(my_write_tool)
install_permission_gate(
  chat, permission_mode = "default",
  tool_meta = list(MyWriteTool = "write"),
  ask_fn = function(name, input, id = NULL) host_prompt(id, name, input))
} # }
```
