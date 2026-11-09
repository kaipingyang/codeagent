# Turns of a saved session as the user saw them

Every turn of the log in order, without the turns a rewind or clear
removed; compaction does not remove anything. For a version 1 file, its
saved turns.

## Usage

``` r
.read_session_display_turns(session_id, cwd = getwd(), tools = list())
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

`list(turns, boundaries)`: ellmer turns, and for each compaction the
number of turns shown before it. `NULL` when the session is not found.
