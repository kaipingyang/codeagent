# Reclaim tasks whose worker died mid-flight

Resets `claimed` tasks that have been held longer than `timeout` seconds
back to `pending` (clearing owner + claimed\_at) so another worker can
pick them up. This is the crash-recovery half of the coordinator: a
worker that dies after claiming a task would otherwise block its
dependents forever. Called from the worker loop's idle branch, so
recovery happens without a separate lead.

## Usage

``` r
board_reclaim_stale(db_path, timeout = 300)
```

## Arguments

  - db\_path:
    
    Character. Board path.

  - timeout:
    
    Numeric. Seconds a `claimed` task may be held before it is
    considered stale (default 300).

## Value

Integer. Number of tasks reclaimed.
