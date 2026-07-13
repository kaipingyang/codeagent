# Session message object (for display/export)

Session message object (for display/export)

## Usage

``` r
SessionMessage(
  type = "user",
  role = NULL,
  text = "",
  uuid = "",
  session_id = ""
)
```

## Arguments

- type:

  Character. "user" or "assistant".

- role:

  Character. Alias for type.

- text:

  Character. Message text.

- uuid:

  Character. Message UUID.

- session_id:

  Character. Session UUID.

## Value

Object of class `SessionMessage`.
