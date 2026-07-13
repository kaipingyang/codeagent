# Watch a task board for changes (event-driven coordinator engine)

Wraps `watcher::watcher()` on the board file so a coordinator / live
Shiny view reacts to board changes the instant they land, instead of
polling. `callback` is invoked (with the changed paths) on every write
to the board. Returns the started watcher (call `$stop()` when done), or
`NULL` when the watcher package is unavailable – callers then fall back
to polling (mirrors how Shiny uses watcher when present and polls
otherwise).

## Usage

``` r
board_watch(db_path, callback, latency = 0.3)
```

## Arguments

  - db\_path:
    
    Character. Board path.

  - callback:
    
    Function of one argument (changed paths).

  - latency:
    
    Numeric. Debounce seconds (default 0.3).

## Value

A started `watcher` R6 object, or `NULL` if watcher is unavailable.
