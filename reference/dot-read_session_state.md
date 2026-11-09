# Read a session's lossless model context (if present)

Version 2: the snapshot of the last `compact_boundary` plus every turn
saved after it (the model sees only what follows the last boundary).
Version 1: its `chat-state` line. `NULL` for text-only legacy sessions
so callers can fall back to text restoration.

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
