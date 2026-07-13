# List codeagent sessions

Scans `~/.codeagent/projects/` for session files.

## Usage

``` r
list_sessions(directory = NULL, limit = NULL, offset = 0L)
```

## Arguments

  - directory:
    
    Character or NULL. Project working directory. When `NULL`, all
    sessions across all projects are listed.

  - limit:
    
    Integer or NULL. Max sessions to return.

  - offset:
    
    Integer. Sessions to skip.

## Value

List of `SessionInfo` objects sorted by `last_modified` descending.
