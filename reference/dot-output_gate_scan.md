# Run the Data Shield output gate on the model's final reply.

Call this AFTER the model's reply is finalized, BEFORE returning it to
the user (CLI) or as a post-stream check (Shiny). No-op when no shield
is active.

## Usage

``` r
.output_gate_scan(text, settings = list(), chat = NULL, on_progress = NULL)
```

## Arguments

- text:

  Character scalar. The model's final reply.

- settings:

  The agent settings list (`data_shield_engine`,
  `data_shield_response_on_fail`, `data_shield_output_scanners`).

- chat:

  The ellmer Chat (fallback shield source via attribute).

- on_progress:

  Optional progress callback forwarded to `scan_response()`.

## Value

A list: `action` (`"pass"`/`"redact"`/`"block"`), `text` (the
possibly-redacted reply), and `matches` (count). When no shield is
active, returns `list(action = "pass", text = text)`.
