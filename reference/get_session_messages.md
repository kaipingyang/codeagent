# Get messages from a session

Get messages from a session

## Usage

``` r
get_session_messages(session_id, directory = NULL, limit = NULL, offset = 0L)
```

## Arguments

- session_id:

  Character. UUID.

- directory:

  Character or NULL. Project directory.

- limit:

  Integer or NULL. Max messages.

- offset:

  Integer. Messages to skip.

## Value

List of `SessionMessage` objects.
