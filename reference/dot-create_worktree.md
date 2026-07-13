# Create an isolated git worktree for a sub-agent

Creates a temporary git worktree so the sub-agent can make changes
without affecting the main working tree. The caller is responsible for
cleanup via `.cleanup_worktree()`.

## Usage

``` r
.create_worktree(base_dir = getwd())
```

## Arguments

  - base\_dir:
    
    Character. Git repo root (default current dir).

## Value

Character. Path to new worktree, or NULL if git not available.
