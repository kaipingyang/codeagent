# Three-Layer Resource Management

Manages large tool output to prevent context bloat.

- **Layer 1** (utils.R): Per-tool character truncation via
  [`truncate_tool_result()`](https://kaipingyang.github.io/codeagent/reference/truncate_tool_result.md).
  Already applied at tool execution time.

- **Layer 2** (this file): Disk persistence for very large results.
  Content \> 5 KB is saved to `~/.codeagent/tool-results/`; a preview +
  file path is injected into the conversation instead.

- **Layer 3** (this file): `ContentReplacementState` – global budget
  tracker that replaces the largest old tool results across turns when
  total context exceeds a soft ceiling.
