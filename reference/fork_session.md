# Fork a session

Creates an independent copy of an existing session JSONL file under a
new UUID. A `session-fork` header entry is prepended to the copy so that
the origin can be traced.

## Usage

``` r
fork_session(session_id, directory = NULL)
```

## Arguments

  - session\_id:
    
    Character. UUID of the session to fork.

  - directory:
    
    Character or NULL. Project working directory used to locate the
    source file and write the fork.

## Value

Character(1). The new session UUID.
