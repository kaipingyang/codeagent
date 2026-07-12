# Read a session's lossless chat-state (if present)

Scans the session file for a `chat-state` line and decodes it into
ellmer turns. Returns `NULL` if the session predates lossless state
(legacy text-only sessions) so callers can fall back to text
restoration.

## Usage

``` r
.read_session_state(session_id, cwd = getwd(), tools = list())
```

## Arguments

- session_id:

  Character. Session UUID.

- cwd:

  Character. Project directory.

- tools:

  List of
  [`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html)
  objects to rebind on replay.

## Value

List of ellmer turns, or `NULL`.
