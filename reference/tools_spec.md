# Tool selection spec

Resolves the `tools=` argument of
[`codeagent_client()`](https://kaipingyang.github.io/codeagent/reference/codeagent_client.md)
into the concrete set of tools to register. One capability namespace
covers codeagent-native groups (`.CODEAGENT_GROUPS`) and btw groups
(`.BTW_GROUPS`); see `.tool_group()`.
