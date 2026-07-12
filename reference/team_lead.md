# LLM-lead autonomous coordinator

A bounded "lead" loop that faithfully ports Claude Code's
COORDINATOR_MODE: a lead model decomposes a high-level goal into a task
DAG, a work-stealing team
([`team_coordinate()`](https://github.com/kaipingyang/codeagent/reference/team_coordinate.md))
auto-claims and runs it, then the lead reviews the results and either
declares the goal done or adds a follow-up round – repeating up to
`max_rounds`.

The three LLM/execution steps are injectable (`decompose_fn`,
`review_fn`, `coordinate_fn`) so the loop control is unit-testable
without a live model; the defaults are ellmer structured-output calls +
the real board.

## Usage

``` r
team_lead(
  goal,
  model = NULL,
  cwd = getwd(),
  max_rounds = 3L,
  n_workers = NULL,
  permission_mode = "bypass",
  worktree = FALSE,
  decompose_fn = NULL,
  review_fn = NULL,
  coordinate_fn = NULL
)
```

## Arguments

- goal:

  Character(1). The high-level objective.

- model:

  Character. Model spec for the lead and the workers.

- cwd:

  Character. Working directory.

- max_rounds:

  Integer. Maximum decompose/review rounds (default 3).

- n_workers, permission_mode, worktree:

  Passed to
  [`team_coordinate()`](https://github.com/kaipingyang/codeagent/reference/team_coordinate.md).

- decompose_fn, review_fn, coordinate_fn:

  Injectable steps (for testing); default to ellmer structured calls +
  the real board.

## Value

A data.frame: every task run across all rounds (with a `round` column).
