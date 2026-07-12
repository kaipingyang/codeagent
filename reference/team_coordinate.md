# Coordinate a team of agents over a shared task board

Seeds a SQLite board with `tasks`, launches `n_workers` mirai daemons,
and has each worker loop: atomically claim the next task, run it as a
codeagent query, write the result back, repeat until the board is empty.
Unlike
[`team_run()`](https://github.com/kaipingyang/codeagent/reference/team_run.md)
(a fixed fan-out where worker i always gets task i), this is a
work-stealing pool – a fast worker claims more tasks, so uneven task
sizes are balanced automatically. Mirrors Claude Code's TeamCreate +
auto-claim.

## Usage

``` r
team_coordinate(
  tasks,
  model = NULL,
  n_workers = NULL,
  permission_mode = "bypass",
  cwd = getwd(),
  blocked_by = NULL,
  worktree = FALSE,
  backoff = 0.5,
  reclaim_timeout = 300,
  db_path = tempfile(fileext = ".sqlite")
)
```

## Arguments

- tasks:

  Character vector of task prompts.

- model:

  Character. Model spec for each worker.

- n_workers:

  Integer or NULL. Worker count; default cgroup-aware
  (`min(#tasks, parallelly::availableCores())`).

- permission_mode:

  Character. Permission mode for workers (default `"bypass"`; parallel
  workers cannot prompt).

- cwd:

  Character. Working directory for workers.

- db_path:

  Character. Board path (created if missing).

## Value

A data.frame: the final board (id, prompt, owner, status, result).
