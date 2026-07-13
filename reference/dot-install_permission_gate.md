# Install the central permission gate on a Chat (idempotent per chat)

Registers ONE `on_tool_request` callback (+ one `on_tool_result` for
PostToolUse) that gates every tool by name. Safe to call repeatedly on
the same chat: the first call installs the callbacks; later calls only
refresh the live context (mode / ask\_fn / policy / hooks), so the Shiny
path can wire `shiny_ask_fn` after the client was built without stacking
a second (denying) gate.

## Usage

``` r
.install_permission_gate(
  chat,
  settings,
  mode_env,
  rules = list(),
  ask_fn = NULL,
  hooks = NULL
)
```

## Arguments

  - chat:
    
    An `ellmer::Chat`.

  - settings:
    
    Named list (for `settings$tools` policy).

  - mode\_env:
    
    Environment with `$mode` (live permission mode) or a string.

  - rules:
    
    List of fine-grained permission rules.

  - ask\_fn:
    
    `function(name, input)` returning logical or promise, or NULL (then
    `"ask"` becomes deny).

  - hooks:
    
    A `HookRegistry` or NULL (fires
    PreToolUse/PostToolUse/PermissionDenied).

## Value

Invisibly `chat`.

## Details

Works for sync (`$chat()`) and async (`$chat_async()`/Shiny): when the
decision is `"ask"` and `ask_fn` returns a promise, the gate returns a
promise the async loop awaits (UI approval); a logical `ask_fn` is
handled inline.
