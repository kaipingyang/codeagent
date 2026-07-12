# Read messages from the team message log

Read messages from the team message log

## Usage

``` r
board_messages(db_path, recipient = NULL)
```

## Arguments

- db_path:

  Character. Board path.

- recipient:

  Character or NULL. If set, returns messages addressed to this
  recipient or broadcast (NULL recipient); otherwise all messages.

## Value

A data.frame of messages.
