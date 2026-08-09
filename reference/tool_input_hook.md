# Tool input rewrite (PreToolUse updatedInput)

Lets a PreToolUse hook rewrite a tool's arguments before it executes,
aligning with the Claude Agent SDK's `updatedInput` contract. ellmer's
`on_tool_request` is rejectable-only (a callback can deny but not
rewrite the request), so the rewrite is done one layer in: each tool
function is wrapped in a closure that runs `HookRegistry$run_pre()` and,
if a hook returned `updated_input`, calls the original with the new
arguments.

Execution order is `gate (on_tool_request) -> this wrapper -> original`,
so the permission gate always sees the ORIGINAL arguments (a rewrite
cannot bypass permission checks – matching the SDK's
permission-then-updatedInput ordering). The tool's JSON schema is
unaffected: ellmer derives it from the `@arguments` slot, independent of
the wrapped function's formals.
