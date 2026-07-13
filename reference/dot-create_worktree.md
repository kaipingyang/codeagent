# Create an isolated git worktree for a sub-agent

Creates a temporary git worktree so the sub-agent can make changes
without affecting the main working tree. The caller is responsible for
cleanup via
[`.cleanup_worktree()`](https://kaipingyang.github.io/codeagent/reference/dot-cleanup_worktree.md).

## Usage

``` r
.create_worktree(base_dir = getwd())
```

## Arguments

- base_dir:

  Character. Git repo root (default current dir).

## Value

Character. Path to new worktree, or NULL if git not available.
