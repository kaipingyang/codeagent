# Tool hook registry

Tool hook registry

Tool hook registry

## Details

Manages lifecycle hooks. Hooks are registered per event type and run in
registration order.

### PreToolUse callback: `function(tool_name, tool_input)`

Returns list with `action`:

- `"allow"` – proceed normally

- `"deny"` – block execution (add optional `message`)

- `"updated_input"` – replace input with `input` field

### PostToolUse callback: `function(tool_name, tool_input, tool_output)`

Returns list with `action`:

- `"allow"` – pass output unchanged

- `"updated_output"` – replace output with `output` field

### PostToolUseFailure callback: `function(tool_name, tool_input, error_message)`

Return value ignored (informational only).

### PermissionDenied callback: `function(tool_name, tool_input, mode)`

Return value ignored (informational only).

### PermissionRequest callback: `function(tool_name, tool_input, mode)`

Returns list with `action`:

- `"allow"` – grant permission

- `"deny"` – reject

- NULL / `"ask"` – fall through to default ask_fn

### UserMessage callback: `function(message)`

Return value ignored (informational only).

### AssistantMessage callback: `function(message)`

Return value ignored (informational only).

## Methods

### Public methods

- [`HookRegistry$new()`](#method-HookRegistry-new)

- [`HookRegistry$register()`](#method-HookRegistry-register)

- [`HookRegistry$register_pre()`](#method-HookRegistry-register_pre)

- [`HookRegistry$register_post()`](#method-HookRegistry-register_post)

- [`HookRegistry$run_pre()`](#method-HookRegistry-run_pre)

- [`HookRegistry$run_post()`](#method-HookRegistry-run_post)

- [`HookRegistry$run_failure()`](#method-HookRegistry-run_failure)

- [`HookRegistry$run_permission_denied()`](#method-HookRegistry-run_permission_denied)

- [`HookRegistry$run_permission_request()`](#method-HookRegistry-run_permission_request)

- [`HookRegistry$run_user_message()`](#method-HookRegistry-run_user_message)

- [`HookRegistry$run_assistant_message()`](#method-HookRegistry-run_assistant_message)

- [`HookRegistry$run_session_start()`](#method-HookRegistry-run_session_start)

- [`HookRegistry$run_stop()`](#method-HookRegistry-run_stop)

- [`HookRegistry$run_pre_compact()`](#method-HookRegistry-run_pre_compact)

- [`HookRegistry$run_subagent_start()`](#method-HookRegistry-run_subagent_start)

- [`HookRegistry$run_subagent_stop()`](#method-HookRegistry-run_subagent_stop)

- [`HookRegistry$clear()`](#method-HookRegistry-clear)

- [`HookRegistry$count()`](#method-HookRegistry-count)

------------------------------------------------------------------------

### Method `new()`

Create a new registry.

#### Usage

    HookRegistry$new()

------------------------------------------------------------------------

### Method `register()`

Register a hook for an event.

#### Usage

    HookRegistry$register(event, fn, tool_pattern = NULL, timeout_ms = 2000L)

#### Arguments

- `event`:

  Character. One of
  [HookEvent](https://github.com/kaipingyang/codeagent/reference/HookEvent.md)
  values.

- `fn`:

  Function. Hook callback.

- `tool_pattern`:

  Character or NULL. Glob filter for tool name (only applies to
  tool-related events).

- `timeout_ms`:

  Integer. Max ms before warning (default 2000).

------------------------------------------------------------------------

### Method `register_pre()`

Register a PreToolUse hook (legacy shorthand).

#### Usage

    HookRegistry$register_pre(fn, tool_pattern = NULL, timeout_ms = 2000L)

------------------------------------------------------------------------

### Method `register_post()`

Register a PostToolUse hook (legacy shorthand).

#### Usage

    HookRegistry$register_post(fn, tool_pattern = NULL, timeout_ms = 2000L)

------------------------------------------------------------------------

### Method `run_pre()`

Fire PreToolUse hooks.

#### Usage

    HookRegistry$run_pre(tool_name, tool_input)

------------------------------------------------------------------------

### Method `run_post()`

Fire PostToolUse hooks.

#### Usage

    HookRegistry$run_post(tool_name, tool_input, tool_output)

------------------------------------------------------------------------

### Method `run_failure()`

Fire PostToolUseFailure hooks (informational).

#### Usage

    HookRegistry$run_failure(tool_name, tool_input, error_message)

------------------------------------------------------------------------

### Method `run_permission_denied()`

Fire PermissionDenied hooks (informational).

#### Usage

    HookRegistry$run_permission_denied(tool_name, tool_input, mode)

------------------------------------------------------------------------

### Method `run_permission_request()`

Fire PermissionRequest hooks. Returns "allow", "deny", or NULL (fall
through to ask_fn).

#### Usage

    HookRegistry$run_permission_request(tool_name, tool_input, mode)

------------------------------------------------------------------------

### Method `run_user_message()`

Fire UserMessage hooks (informational).

#### Usage

    HookRegistry$run_user_message(message)

------------------------------------------------------------------------

### Method `run_assistant_message()`

Fire AssistantMessage hooks (informational).

#### Usage

    HookRegistry$run_assistant_message(message)

------------------------------------------------------------------------

### Method `run_session_start()`

Fire SessionStart hooks at the top of a session/turn. Callback:
`function(context)`. Return value ignored.

#### Usage

    HookRegistry$run_session_start(context = list())

------------------------------------------------------------------------

### Method `run_stop()`

Fire Stop hooks when the agent loop terminates. Callback:
`function(stop_reason, context)`. Return value ignored.

#### Usage

    HookRegistry$run_stop(stop_reason = "completed", context = list())

------------------------------------------------------------------------

### Method `run_pre_compact()`

Fire PreCompact hooks before context compaction. Callback:
`function(level, context)`. Return value ignored.

#### Usage

    HookRegistry$run_pre_compact(level = "unknown", context = list())

------------------------------------------------------------------------

### Method `run_subagent_start()`

Fire SubagentStart hooks when a sub-agent is launched. Callback:
`function(description, context)`. Return value ignored.

#### Usage

    HookRegistry$run_subagent_start(description = "", context = list())

------------------------------------------------------------------------

### Method `run_subagent_stop()`

Fire SubagentStop hooks when a sub-agent completes. Callback:
`function(description, result, context)`. Return ignored.

#### Usage

    HookRegistry$run_subagent_stop(
      description = "",
      result = NULL,
      context = list()
    )

------------------------------------------------------------------------

### Method `clear()`

Remove all registered hooks.

#### Usage

    HookRegistry$clear()

------------------------------------------------------------------------

### Method `count()`

Count total registered hooks across all events.

#### Usage

    HookRegistry$count()
