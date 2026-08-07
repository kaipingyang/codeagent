# Tool hook registry

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

### UserPromptSubmit callback: `function(message)`

Aligns with Claude Code's `UserPromptSubmit` contract. Returns a list
with `action`:

- `"allow"` (or NULL) – proceed unchanged

- `"block"` – reject this turn; the user prompt never reaches the model
  (optional `message` becomes the response shown instead)

- `"add_context"` – proceed, but APPEND `additional_context` to what is
  sent to the model (never rewrites the user's original text – matching
  CC, which only supports block + additionalContext, not redaction of
  user input)

### AssistantMessage callback: `function(message)`

Return value ignored (informational only).

## Methods

### Public methods

- [`HookRegistry$new()`](#method-HookRegistry-initialize)

- [`HookRegistry$register()`](#method-HookRegistry-register)

- [`HookRegistry$register_pre()`](#method-HookRegistry-register_pre)

- [`HookRegistry$register_post()`](#method-HookRegistry-register_post)

- [`HookRegistry$run_pre()`](#method-HookRegistry-run_pre)

- [`HookRegistry$run_post()`](#method-HookRegistry-run_post)

- [`HookRegistry$run_failure()`](#method-HookRegistry-run_failure)

- [`HookRegistry$run_permission_denied()`](#method-HookRegistry-run_permission_denied)

- [`HookRegistry$run_permission_request()`](#method-HookRegistry-run_permission_request)

- [`HookRegistry$run_user_prompt_submit()`](#method-HookRegistry-run_user_prompt_submit)

- [`HookRegistry$run_assistant_message()`](#method-HookRegistry-run_assistant_message)

- [`HookRegistry$run_session_start()`](#method-HookRegistry-run_session_start)

- [`HookRegistry$run_stop()`](#method-HookRegistry-run_stop)

- [`HookRegistry$run_pre_compact()`](#method-HookRegistry-run_pre_compact)

- [`HookRegistry$run_subagent_start()`](#method-HookRegistry-run_subagent_start)

- [`HookRegistry$run_subagent_stop()`](#method-HookRegistry-run_subagent_stop)

- [`HookRegistry$run_session_end()`](#method-HookRegistry-run_session_end)

- [`HookRegistry$run_post_compact()`](#method-HookRegistry-run_post_compact)

- [`HookRegistry$run_stop_failure()`](#method-HookRegistry-run_stop_failure)

- [`HookRegistry$run_notification()`](#method-HookRegistry-run_notification)

- [`HookRegistry$run_task_created()`](#method-HookRegistry-run_task_created)

- [`HookRegistry$run_task_completed()`](#method-HookRegistry-run_task_completed)

- [`HookRegistry$run_worktree_create()`](#method-HookRegistry-run_worktree_create)

- [`HookRegistry$run_worktree_remove()`](#method-HookRegistry-run_worktree_remove)

- [`HookRegistry$run_instructions_loaded()`](#method-HookRegistry-run_instructions_loaded)

- [`HookRegistry$run_file_changed()`](#method-HookRegistry-run_file_changed)

- [`HookRegistry$run_config_change()`](#method-HookRegistry-run_config_change)

- [`HookRegistry$clear()`](#method-HookRegistry-clear)

- [`HookRegistry$count()`](#method-HookRegistry-count)

- [`HookRegistry$has_hooks()`](#method-HookRegistry-has_hooks)

------------------------------------------------------------------------

### `HookRegistry$new()`

Create a new registry.

#### Usage

    HookRegistry$new()

------------------------------------------------------------------------

### `HookRegistry$register()`

Register a hook for an event.

#### Usage

    HookRegistry$register(event, fn, tool_pattern = NULL, timeout_ms = 2000L)

#### Arguments

- `event`:

  Character. One of
  [HookEvent](https://kaipingyang.github.io/codeagent/reference/HookEvent.md)
  values.

- `fn`:

  Function. Hook callback.

- `tool_pattern`:

  Character or NULL. Glob filter for tool name (only applies to
  tool-related events).

- `timeout_ms`:

  Integer. Max ms before warning (default 2000).

------------------------------------------------------------------------

### `HookRegistry$register_pre()`

Register a PreToolUse hook (legacy shorthand).

#### Usage

    HookRegistry$register_pre(fn, tool_pattern = NULL, timeout_ms = 2000L)

------------------------------------------------------------------------

### `HookRegistry$register_post()`

Register a PostToolUse hook (legacy shorthand).

#### Usage

    HookRegistry$register_post(fn, tool_pattern = NULL, timeout_ms = 2000L)

------------------------------------------------------------------------

### `HookRegistry$run_pre()`

Fire PreToolUse hooks.

#### Usage

    HookRegistry$run_pre(tool_name, tool_input)

------------------------------------------------------------------------

### `HookRegistry$run_post()`

Fire PostToolUse hooks.

#### Usage

    HookRegistry$run_post(tool_name, tool_input, tool_output)

------------------------------------------------------------------------

### `HookRegistry$run_failure()`

Fire PostToolUseFailure hooks (informational).

#### Usage

    HookRegistry$run_failure(tool_name, tool_input, error_message)

------------------------------------------------------------------------

### `HookRegistry$run_permission_denied()`

Fire PermissionDenied hooks (informational).

#### Usage

    HookRegistry$run_permission_denied(tool_name, tool_input, mode)

------------------------------------------------------------------------

### `HookRegistry$run_permission_request()`

Fire PermissionRequest hooks. Returns "allow", "deny", or NULL (fall
through to ask_fn).

#### Usage

    HookRegistry$run_permission_request(tool_name, tool_input, mode)

------------------------------------------------------------------------

### `HookRegistry$run_user_prompt_submit()`

Fire UserPromptSubmit hooks (before the prompt reaches the model).
Aligns with Claude Code's `UserPromptSubmit`: a hook may `block` the
turn or append `additional_context`, but NEVER rewrites the user's
original text. Returns a list: `list(action = "block", message = ...)`
if any hook blocked, else
`list(action = "allow", additional_context = <appended text or NULL>)`.

#### Usage

    HookRegistry$run_user_prompt_submit(message)

------------------------------------------------------------------------

### `HookRegistry$run_assistant_message()`

Fire AssistantMessage hooks (informational).

#### Usage

    HookRegistry$run_assistant_message(message)

------------------------------------------------------------------------

### `HookRegistry$run_session_start()`

Fire SessionStart hooks at the top of a session/turn. Callback:
`function(context)`. Return value ignored.

#### Usage

    HookRegistry$run_session_start(context = list())

------------------------------------------------------------------------

### `HookRegistry$run_stop()`

Fire Stop hooks when the agent loop terminates. Callback:
`function(stop_reason, context)`. Return value ignored.

#### Usage

    HookRegistry$run_stop(stop_reason = "completed", context = list())

------------------------------------------------------------------------

### `HookRegistry$run_pre_compact()`

Fire PreCompact hooks before context compaction. Callback:
`function(level, context)`. Return value ignored.

#### Usage

    HookRegistry$run_pre_compact(level = "unknown", context = list())

------------------------------------------------------------------------

### `HookRegistry$run_subagent_start()`

Fire SubagentStart hooks when a sub-agent is launched. Callback:
`function(description, context)`. Return value ignored.

#### Usage

    HookRegistry$run_subagent_start(description = "", context = list())

------------------------------------------------------------------------

### `HookRegistry$run_subagent_stop()`

Fire SubagentStop hooks when a sub-agent completes. Callback:
`function(description, result, context)`. Return ignored.

#### Usage

    HookRegistry$run_subagent_stop(
      description = "",
      result = NULL,
      context = list()
    )

------------------------------------------------------------------------

### `HookRegistry$run_session_end()`

Fire SessionEnd hooks when the agent loop terminates. Callback:
`function(reason, context)`. Return value ignored. `reason` mirrors CC's
exit reasons where they map (e.g. "completed", "max_turns",
"budget_exceeded", "error").

#### Usage

    HookRegistry$run_session_end(reason = "completed", context = list())

------------------------------------------------------------------------

### `HookRegistry$run_post_compact()`

Fire PostCompact hooks after context compaction completes. Callback:
`function(trigger, compact_summary, context)`. Return ignored.

#### Usage

    HookRegistry$run_post_compact(
      trigger = "auto",
      compact_summary = "",
      context = list()
    )

------------------------------------------------------------------------

### `HookRegistry$run_stop_failure()`

Fire StopFailure hooks when the loop ends on an error. Callback:
`function(error, context)`. Return value ignored.

#### Usage

    HookRegistry$run_stop_failure(error = "", context = list())

------------------------------------------------------------------------

### `HookRegistry$run_notification()`

Fire Notification hooks for user-facing notifications. Callback:
`function(message, notification_type, context)`. Return ignored.

#### Usage

    HookRegistry$run_notification(
      message = "",
      notification_type = "info",
      context = list()
    )

------------------------------------------------------------------------

### `HookRegistry$run_task_created()`

Fire TaskCreated hooks when a task is created. Callback:
`function(task_id, task_subject, context)`. Return ignored.

#### Usage

    HookRegistry$run_task_created(
      task_id = "",
      task_subject = "",
      context = list()
    )

------------------------------------------------------------------------

### `HookRegistry$run_task_completed()`

Fire TaskCompleted hooks when a task becomes completed. Callback:
`function(task_id, task_subject, context)`. Return ignored.

#### Usage

    HookRegistry$run_task_completed(
      task_id = "",
      task_subject = "",
      context = list()
    )

------------------------------------------------------------------------

### `HookRegistry$run_worktree_create()`

Fire WorktreeCreate hooks when a sub-agent worktree is made. Callback:
`function(name, context)`. Return value ignored.

#### Usage

    HookRegistry$run_worktree_create(name = "", context = list())

------------------------------------------------------------------------

### `HookRegistry$run_worktree_remove()`

Fire WorktreeRemove hooks when a sub-agent worktree is removed.
Callback: `function(worktree_path, context)`. Return value ignored.

#### Usage

    HookRegistry$run_worktree_remove(worktree_path = "", context = list())

------------------------------------------------------------------------

### `HookRegistry$run_instructions_loaded()`

Fire InstructionsLoaded hooks when a CLAUDE.md file loads. Callback:
`function(file_path, memory_type, load_reason, context)`. Return
ignored. NOTE: `memory_type` is a best-effort approximation
(User/Project by path prefix; no Managed concept) and `load_reason` is
always "session_start" – codeagent has no nested/glob/include/compact
load paths, so these fields are NOT field-for-field equal to CC.

#### Usage

    HookRegistry$run_instructions_loaded(
      file_path = "",
      memory_type = "Project",
      load_reason = "session_start",
      context = list()
    )

------------------------------------------------------------------------

### `HookRegistry$run_file_changed()`

Fire FileChanged hooks (Shiny-only; watcher-driven). Callback:
`function(file_path, event, context)` where `event` is one of
"change"/"add"/"unlink". Return value ignored. Not fired on the CLI –
the synchronous CLI loop cannot pump the `later` queue watcher needs.

#### Usage

    HookRegistry$run_file_changed(
      file_path = "",
      event = "change",
      context = list()
    )

------------------------------------------------------------------------

### `HookRegistry$run_config_change()`

Fire ConfigChange hooks (Shiny-only; watcher-driven). Callback:
`function(source, file_path, context)`. Return value ignored. Not fired
on the CLI (see run_file_changed note).

#### Usage

    HookRegistry$run_config_change(
      source = "user_settings",
      file_path = "",
      context = list()
    )

------------------------------------------------------------------------

### `HookRegistry$clear()`

Remove all registered hooks.

#### Usage

    HookRegistry$clear()

------------------------------------------------------------------------

### `HookRegistry$count()`

Count total registered hooks across all events.

#### Usage

    HookRegistry$count()

------------------------------------------------------------------------

### `HookRegistry$has_hooks()`

TRUE if at least one hook is registered for `event`.

#### Usage

    HookRegistry$has_hooks(event)

#### Arguments

- `event`:

  Character. One of
  [HookEvent](https://kaipingyang.github.io/codeagent/reference/HookEvent.md)
  values.
