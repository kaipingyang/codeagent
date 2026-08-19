# Model Switching (harness, no Shiny dependency)

Lossless mid-conversation model switching. Pure-R harness functions
usable from both the CLI and the Shiny app. Conversation history
(including tool requests/results) is preserved across the switch.

Two strategies:

- **Route A (strict name-only)** – use public `set_model()` only when
  the provider configuration and Model params/extra args are unchanged.
  Chat identity, callbacks, and tools remain intact.

- **Route B (fallback)** – for provider/configuration changes, build a
  fresh Chat, migrate turns, and rebuild tools while carrying forward
  the complete live client settings, hooks, and Data Shield engine.
  Returns a NEW client object; the original remains unchanged if
  rebuilding fails.

See `references/model-switch-alternatives.md` for the 13-point empirical
validation behind this design.
