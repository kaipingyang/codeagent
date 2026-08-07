# Prompt Gate — the edge-1 counterpart of the tool gate

The tool gate (`R/tools_gate.R`) guards edge 2 (tool traffic) by
wrapping ellmer's `on_tool_request` / tool functions. The **prompt
gate** guards edge 1: the user's message *before it reaches the model*.
Unlike the tool gate it has no ellmer chat-level hook to attach to (user
input is handled inside `agent_loop`, not inside the Chat object), so
the prompt gate is a function the agent loop calls at the
UserPromptSubmit point.

Two consumers run at this edge, in order (mirroring the tool gate's
hooks-then-shield layering), kept as SEPARATE systems:

1.  **hooks** `run_user_prompt_submit()` – aligns with Claude Code's
    `UserPromptSubmit`; may `block` or append context, NEVER redacts
    (handled in `agent_loop` directly).

2.  **Data Shield** `scan_prompt()` – the shield's own confidentiality
    scan; MAY redact (protected values / PII the user pasted in). This
    file wires that second consumer.
