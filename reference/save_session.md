# Save an ellmer Chat session to disk

Serialises all turns in `chat` to a JSONL file under
`~/.codeagent/projects/<project_hash>/<session_id>.jsonl`.

## Usage

``` r
save_session(
  chat,
  cwd = getwd(),
  session_id = NULL,
  title = NULL,
  assistant_text_override = NULL
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
  presentation line. Lossless chat-state remains intact.

## Value

Character(1). The session UUID.
