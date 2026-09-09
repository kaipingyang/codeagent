# Three-Layer Resource Management

Manages large tool output to prevent context bloat.

- **Layer 1** (utils.R): Per-tool character truncation via
  [`truncate_tool_result()`](https://kaipingyang.github.io/codeagent/reference/truncate_tool_result.md).
  Already applied at tool execution time.

- **Layer 2** (this file): Optional disk-persistence helper for very
  large results. It is intentionally NOT wired into production until
  file permissions, retention/cleanup, path disclosure, and
  protected-data policy are defined; built-in truncation remains the
  active protection.

- **Layer 3** (this file): `ContentReplacementState` – global budget
  tracker that replaces the largest old tool results across turns when
  total context exceeds a soft ceiling.
