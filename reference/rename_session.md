# Rename a session

Appends a `custom-title` JSONL entry. Repeated calls are safe –
`list_sessions()` reads the last custom-title (most recent wins).

## Usage

``` r
rename_session(session_id, title, directory = NULL)
```

## Arguments

  - session\_id:
    
    Character. UUID of the session.

  - title:
    
    Character. New title (non-empty after trimming).

  - directory:
    
    Character or NULL. Project working directory.

## Value

Invisibly NULL.
