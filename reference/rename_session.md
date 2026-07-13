# Rename a session

Appends a `custom-title` JSONL entry. Repeated calls are safe –
[`list_sessions()`](https://kaipingyang.github.io/codeagent/reference/list_sessions.md)
reads the last custom-title (most recent wins).

## Usage

``` r
rename_session(session_id, title, directory = NULL)
```

## Arguments

- session_id:

  Character. UUID of the session.

- title:

  Character. New title (non-empty after trimming).

- directory:

  Character or NULL. Project working directory.

## Value

Invisibly NULL.
