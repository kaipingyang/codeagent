# Run the Data Shield prompt gate on a user message.

Call this in the agent loop AFTER the UserPromptSubmit hook, BEFORE the
prompt is sent to the model. It resolves the active shield the same way
the tool gate does (settings engine first, then the chat attribute) and
applies `scan_prompt()`.

## Usage

``` r
.prompt_gate_scan(
  user_input,
  settings = list(),
  chat = NULL,
  on_progress = NULL
)
```

## Arguments

- user_input:

  Character scalar. The raw user prompt (post-hook).

- settings:

  The agent settings list (for `data_shield_engine`).

- chat:

  The ellmer Chat (fallback shield source via attribute).

- on_progress:

  Optional progress callback forwarded to `scan_prompt()`.

## Value

A list: `action` (`"pass"`/`"redact"`/`"block"`/`"ask"`) and `text`
(possibly redacted prompt). `"pass"`/`"redact"` mean "continue with
`text`"; `"block"` means "reject this turn"; `"ask"` currently degrades
to redact at this call site unless the caller wires an approval path.
When no shield is active, returns
`list(action = "pass", text = user_input)`.
