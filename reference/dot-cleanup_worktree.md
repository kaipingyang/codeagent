# Remove a git worktree

Remove a git worktree

## Usage

``` r
.cleanup_worktree(wt_path, base_dir = getwd())
```

## Arguments

- wt_path:

  Character. Path returned by
  [`.create_worktree()`](https://github.com/kaipingyang/codeagent/reference/dot-create_worktree.md).

- base_dir:

  Character. The repo the worktree belongs to (so `git worktree remove`
  has repo context even if cwd has changed). Defaults to the current
  directory.
