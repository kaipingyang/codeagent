# Built-in Tools Registration

Registers all core codeagent tools (Bash, Read, Write, Edit, MultiEdit,
Glob, Grep, LS) onto an ellmer Chat. Individual tool factories live in
dedicated files:
[tools\_bash](https://kaipingyang.github.io/codeagent/reference/tools_bash.md),
[tools\_fs](https://kaipingyang.github.io/codeagent/reference/tools_fs.md),
[tools\_search](https://kaipingyang.github.io/codeagent/reference/tools_search.md).

Shared helpers used by all tool files:

  - `.tool_result()` – legacy ContentToolResult builder

  - `.make_permission_checker()` – live-mode permission closure factory
