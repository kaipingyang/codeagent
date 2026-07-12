# Atomically claim the next claimable task (dependency-aware)

Runs inside a `BEGIN IMMEDIATE` transaction (SQLite serialises writers)
and claims the lowest-id task that is unowned, `pending`, and has **no
unfinished blocker** (all its `deps` blockers are `done`). With no deps
this is exactly the old FIFO claim (backward compatible). Returns `NULL`
when nothing is currently claimable – which may mean "all done" OR
"remaining tasks are still blocked", so a worker should back off and
retry rather than exit (see `team_coordinate`).

## Usage

``` r
board_claim(db_path, worker_id)
```

## Arguments

- db_path:

  Character. Board path.

- worker_id:

  Character. Identifier for the claiming worker.

## Value

A one-row data.frame (id, prompt) for the claimed task, or NULL.
