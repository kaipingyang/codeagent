# Convert a skill prompt to shinychat slash-command content

Convert a skill prompt to shinychat slash-command content

## Usage

``` r
.as_skill_slash_content(input, parsed, redact_user_text = FALSE)
```

## Arguments

- input:

  Character input or a list whose first element is text.

- parsed:

  Parsed slash-command metadata.

- redact_user_text:

  Whether to replace the user arguments with a redaction marker.

## Value

The input with its text converted to `ContentSlashCommand` when the
command is a skill and shinychat provides the constructor.
