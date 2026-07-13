# Build a HookRegistry from a settings.json `hooks` block

Parses a declarative hooks specification (as loaded from settings.json)
into a live
[HookRegistry](https://kaipingyang.github.io/codeagent/reference/HookRegistry.md).
The expected shape mirrors Claude Code:

    "hooks": {
      "PreToolUse":  [{ "command": "echo pre  >> /tmp/hooks.log" }],
      "PostToolUse": [{ "command": "echo post >> /tmp/hooks.log", "pattern": "Bash" }]
    }

Each entry's `command` is run via the shell when the event fires;
`pattern` (optional) limits a tool hook to matching tool names.

## Usage

``` r
.hooks_from_settings(settings)
```

## Arguments

  - settings:
    
    List from `load_settings()` (uses `settings$hooks`).

## Value

A
[HookRegistry](https://kaipingyang.github.io/codeagent/reference/HookRegistry.md),
or NULL if no valid hooks are declared.
