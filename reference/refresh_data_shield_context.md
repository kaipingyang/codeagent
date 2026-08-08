# Refresh the Data Shield schema block in a client's system prompt

Rebuilds the full system prompt (which includes each registered
protected dataset's filtered schema) and re-applies it to the client's
Chat via `set_system_prompt()`. Call this after registering or uploading
data at runtime (e.g. a Shiny `fileInput` handler) so the model sees the
new dataset's schema. Datasets registered before the client was built
are already in the initial system prompt and need no refresh.

## Usage

``` r
refresh_data_shield_context(client)
```

## Arguments

- client:

  A `CodeagentClient` (or a bare ellmer `Chat`, using default
  settings/cwd).

## Value

The `client`, invisibly.

## Details

`set_system_prompt()` replaces the prompt wholesale but preserves the
conversation history (turns), so the running chat is unaffected apart
from a one-time prompt-cache miss.
