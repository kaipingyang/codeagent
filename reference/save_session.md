# Save an ellmer Chat session to disk

Appends the conversation to a JSONL log under
`<CODEAGENT_HOME>/projects/<project>/<session_id>.jsonl` (format version
2). Each new turn is one `user` / `assistant` entry holding its display
text and its lossless record; entries are chained by `uuid` /
`parentUuid`. Turns already in the file are not written again. When the
chat's context is no longer "the saved turns plus new ones" –
compaction, rewind, clear – a `system` / `compact_boundary` entry is
appended with a snapshot of the new context (`parentUuid: null`,
`logicalParentUuid` pointing at the last entry before it), so earlier
turns stay in the file. The model context restores from the last
boundary on
([`restore_session_into_chat()`](https://kaipingyang.github.io/codeagent/reference/restore_session_into_chat.md));
the display keeps every turn. A version 1 file (rewritten whole on every
save) is migrated on its first save.

## Usage

``` r
save_session(
  chat,
  cwd = getwd(),
  session_id = NULL,
  title = NULL,
  assistant_text_override = NULL,
  genui_state = NULL,
  context_event = NULL
)
```

## Arguments

- chat:

  An [`ellmer::Chat`](https://ellmer.tidyverse.org/reference/Chat.html)
  object.

- cwd:

  Character. Working directory (used to key the project).

- session_id:

  Character or NULL. UUID; generated if NULL.

- title:

  Character or NULL. Optional human-readable title.

- assistant_text_override:

  Character or NULL. Safe finalized text for the last assistant turn's
  presentation line. The lossless record keeps the provider-facing turn.

- genui_state:

  List or NULL. The generative UI canvas state to persist with the
  conversation; appended when it differs from the last saved one.

- context_event:

  Character or NULL. What changed the context when it is not a
  continuation (`"compact"`, `"rewind"`, `"clear"`); inferred when NULL.

## Value

Character(1). The session UUID.
