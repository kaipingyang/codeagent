# Input Gate — the edge-1 counterpart of the tool gate

The tool gate (`R/tools_gate.R`) guards edge 2 (tool traffic) by
wrapping ellmer's `on_tool_request` / tool functions. The **input gate**
guards edge 1: everything the user sends *before it reaches the model* —
typed text AND attachments (text-bearing content, images). Unlike the
tool gate it has no ellmer chat-level hook to attach to (user input is
handled inside `agent_loop` / the Shiny stream, not inside the Chat
object), so the input gate is a function those entry points call at the
UserPromptSubmit point.

Two consumers run at this edge, in order (mirroring the tool gate's
hooks-then-shield layering), kept as SEPARATE systems:

1.  **hooks** `run_user_prompt_submit()` – aligns with Claude Code's
    `UserPromptSubmit`; may `block` or append context, NEVER redacts
    (handled in `agent_loop` directly).

2.  **Data Shield** `scan_prompt()` – the shield's own confidentiality
    scan; MAY redact (protected values / PII the user pasted in). This
    file wires that second consumer.

Input types and how each is handled (see `.input_gate_scan`):

- **text** (typed message) -\> `scan_prompt`; redact/block/ask.

- **text-bearing attachment** -\> extract text, scan; cannot be redacted
  in place (Content is immutable) so a hit fails safe to **block**.

- **image attachment** -\> optional `image_scanner` hook (default `NULL`
  = blind spot, passed through). Host may inject a scanner (OCR / VLM)
  returning a decision.
