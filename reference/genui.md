# Generative UI adapter

codeagent-owned adapter over the exported pure functions of shinygenui.
shinygenui decides whether a model call is valid and what plan it
becomes; codeagent turns that plan into DOM and is answerable for it.
`genui_server()` is never called: it would replace the system prompt,
register tools behind the central permission gate, and take stream
ownership. See `references/plan/41-genui-adapter.md`.
