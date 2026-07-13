# Run a one-shot codeagent query

Two calling conventions:

## Usage

``` r
codeagent(
  client_or_prompt,
  prompt = NULL,
  model = "claude-sonnet-4-6",
  permission_mode = "default",
  rules = list(),
  cwd = getwd(),
  max_turns = 100L,
  btw_groups = NULL,
  ...
)
```

## Arguments

  - client\_or\_prompt:
    
    Either a `CodeagentClient` (from `codeagent_client()`) or a
    character prompt string (legacy mode).

  - prompt:
    
    Character. The user prompt. Required when `client_or_prompt` is a
    `CodeagentClient`; unused in legacy mode.

  - model:
    
    Character. Legacy: model name.

  - permission\_mode:
    
    Character. Legacy: permission mode.

  - rules:
    
    List. Legacy: permission rules.

  - cwd:
    
    Character. Legacy: working directory.

  - max\_turns:
    
    Integer. Legacy: max turns.

  - btw\_groups:
    
    Character vector or NULL. Legacy: btw tool groups.

  - ...:
    
    Legacy: extra args passed to `.make_chat()`.

## Value

Character. The final model response.

## Details

**New (recommended):** pass a `codeagent_client()` as first argument.

    client <- codeagent_client(chat_openai_compatible(...), permission_mode = "bypass")
    codeagent(client, "List all .R files")

**Legacy (backward-compatible):** omit client, pass model etc. directly.

    codeagent("List all .R files", model = "gpt-4.1", permission_mode = "bypass")
