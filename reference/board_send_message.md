# Post a message to the team message log

Post a message to the team message log

## Usage

``` r
board_send_message(db_path, sender, body, recipient = NULL)
```

## Arguments

- db_path:

  Character. Board path.

- sender:

  Character. Sender id.

- body:

  Character. Message body.

- recipient:

  Character or NULL. Target agent (NULL = broadcast).

## Value

Invisibly TRUE.
