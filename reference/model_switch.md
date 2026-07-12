# Model Switching (harness, no Shiny dependency)

Lossless mid-conversation model switching. Pure-R harness functions
usable from both the CLI and the Shiny app. Conversation history
(including tool requests/results) is preserved across the switch.

Two strategies:

- **Route A (default)** – swap the ellmer Chat's internal provider in
  place. The Chat object identity is unchanged, so callbacks
  (`on_tool_result`), the stream controller, and any closures capturing
  the Chat keep working untouched. Touches ellmer's private R6 field,
  guarded by tryCatch.

- **Route B (fallback)** – build a fresh Chat from the new spec, migrate
  turns via `set_turns()`, and rebuild the client through
  [`codeagent_client()`](https://github.com/kaipingyang/codeagent/reference/codeagent_client.md)
  (re-registers tools + system prompt). Pure public API; returns a NEW
  client object.

See `references/model-switch-alternatives.md` for the 13-point empirical
validation behind this design.
