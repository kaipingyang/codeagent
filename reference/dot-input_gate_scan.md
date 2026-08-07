# Run the Data Shield input gate on a user turn's input.

Call this in the agent loop / Shiny stream AFTER the UserPromptSubmit
hook, BEFORE the input is sent to the model. Handles both a bare
character scalar (CLI) and a contents list (Shiny: typed text +
attachments).

## Usage

``` r
.input_gate_scan(
  input,
  settings = list(),
  chat = NULL,
  on_progress = NULL,
  image_scanner = NULL
)
```

## Arguments

- input:

  Character scalar OR a list whose first element is the typed text and
  whose remaining elements are ellmer Content attachments.

- settings:

  The agent settings list (`data_shield_engine`,
  `data_shield_prompt_on_fail`, `data_shield_image_scanner`).

- chat:

  The ellmer Chat (fallback shield source via attribute).

- on_progress:

  Optional progress callback forwarded to `scan_prompt()`.

- image_scanner:

  Optional `function(content_image) -> list(action, ...)` for image
  attachments (default resolves from
  `settings$data_shield_image_scanner`; `NULL` = images not scanned).

## Value

A list: `action` (`"pass"`/`"redact"`/`"block"`), `input` (the
possibly-redacted input, same shape as the argument), and `text` (a
message when `action == "block"`). When no shield is active, returns
`list(action = "pass", input = input)`.
