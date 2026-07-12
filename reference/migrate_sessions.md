# Migrate legacy session files to the current format version

Scans all session JSONL files and adds `format_version` to headers that
are missing it. Safe to run multiple times (already-migrated files are
skipped).

## Usage

``` r
migrate_sessions(directory = NULL)
```

## Arguments

- directory:

  Character or NULL. Project working directory; `NULL` scans all
  projects under `~/.codeagent/projects/`.

## Value

Invisibly returns the number of files updated.
