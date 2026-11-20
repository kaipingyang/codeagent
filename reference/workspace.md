# Workspace tabs

The right-panel workspace: one tab per opened thing (a tool result, a
file, a host's own content), keyed by `(kind, content_id)`. Layout logic
lives in
[workspace_layout](https://kaipingyang.github.io/codeagent/reference/workspace_layout.md);
this file holds the kind registry, the UI and the per-session server.
