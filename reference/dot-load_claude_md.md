# Load and merge CLAUDE.md from all levels

Mirrors Claude Code's multi-level memory: collect CLAUDE.md from the
user home (`~/.claude/CLAUDE.md`, `~/.codeagent/CLAUDE.md`) plus every
level from the working directory up to the filesystem root (max 5 hops),
then merge them in priority order (user first, then outer-to-inner
project dirs) with section headers showing each source. More-specific
(deeper) files appear later so they visually override. Duplicate paths
are de-duplicated.

## Usage

``` r
.load_claude_md(cwd)
```

## Arguments

- cwd:

  Character. Starting directory.

## Value

Character(1) with merged contents, or NULL if none found.
