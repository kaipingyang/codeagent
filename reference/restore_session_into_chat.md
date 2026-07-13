# Restore a saved session's messages into a Chat object

Loads a session and replays it into a Chat. Prefers the lossless
`chat-state` record (tool calls/results intact, via
`contents_record()`/`contents_replay()`); falls back to text-level turns
for pre-lossless sessions.

## Usage

``` r
restore_session_into_chat(chat, session_id = NULL, cwd = getwd())
```

## Arguments

  - chat:
    
    An `ellmer::Chat` to populate.

  - session\_id:
    
    Character. Session UUID. If `NULL`, the most recent session under
    `cwd` is used (for `--continue`).

  - cwd:
    
    Character. Project directory for session lookup.

## Value

Invisibly, the resolved session id (or `NULL` if none found).
