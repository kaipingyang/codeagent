# Add a task to the board

Add a task to the board

## Usage

``` r
board_add_task(db_path, prompt, blocked_by = integer(0))
```

## Arguments

- db_path:

  Character. Board path.

- prompt:

  Character. The task prompt.

- blocked_by:

  Integer vector. Task ids that must be `done` before this task can be
  claimed (DAG edges). Default none. Blockers must already exist on the
  board (a new task cannot create a cycle by construction).

## Value

Integer. The new task id.
