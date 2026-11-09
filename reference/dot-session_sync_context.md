# Record a context change in a saved session

Appends a `compact_boundary` to the session's log when the chat's
context is no longer a continuation of what was saved (compaction,
rewind, clear). Called where the context changes – before a turn, after
`/compact`, `/clear`, `/rewind` – so the end-of-turn save only appends
the new turns. A session that has no file yet is left alone.

## Usage

``` r
.session_sync_context(chat, cwd, session_id, context_event = NULL)
```

## Arguments

- chat:

  An [`ellmer::Chat`](https://ellmer.tidyverse.org/reference/Chat.html)
  object.

- cwd:

  Character. Project directory.

- session_id:

  Character or NULL. Session UUID.

- context_event:

  Character or NULL. See
  [`save_session()`](https://kaipingyang.github.io/codeagent/reference/save_session.md).

## Value

Invisibly TRUE when the session file exists.
