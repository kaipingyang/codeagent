# Remove a git worktree

Remove a git worktree

## Usage

``` r
.cleanup_worktree(wt_path, base_dir = getwd())
```

## Arguments

  - wt\_path:
    
    Character. Path returned by `.create_worktree()`.

  - base\_dir:
    
    Character. The repo the worktree belongs to (so `git worktree
    remove` has repo context even if cwd has changed). Defaults to the
    current directory.
