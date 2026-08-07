# Hook event types

Named list of lifecycle event names that can be hooked.

## Usage

``` r
HookEvent
```

## Details

- `PRE_TOOL_USE` – Before tool execution (can allow/deny/modify input)

- `POST_TOOL_USE` – After successful tool execution (can modify output)

- `POST_TOOL_USE_FAILURE` – After a tool throws an error

- `PERMISSION_DENIED` – When a tool call is blocked by permissions

- `PERMISSION_REQUEST` – When permission mode is "ask" (bubble/default)

- `USER_PROMPT_SUBMIT` – When user submits a prompt, before it reaches
  the model (aligns with Claude Code's public `UserPromptSubmit` hook
  event) (codeagent's name for Claude Code's `UserPromptSubmit`)

- `ASSISTANT_MESSAGE` – When the assistant produces a text response.
  NOTE: name collides with Claude Agent SDK's `AssistantMessage`
  *message type* but is used here as a *hook event*; Claude Code has no
  such event (it uses `Stop` + `last_assistant_message`). Kept for its
  downstream consumer (ui_customizations.R); TODO: evaluate merging into
  `Stop`.

- `SESSION_END` – When the agent loop terminates (any reason)

- `POST_COMPACT` – After context compaction completes

- `STOP_FAILURE` – When the loop terminates on an error

- `NOTIFICATION` – Generic user-facing notification

- `TASK_CREATED` – When a task is created (TaskCreate tool)

- `TASK_COMPLETED` – When a task transitions to completed

- `WORKTREE_CREATE` – When a sub-agent git worktree is created

- `WORKTREE_REMOVE` – When a sub-agent git worktree is removed

- `INSTRUCTIONS_LOADED` – When a CLAUDE.md instruction file is loaded

- `FILE_CHANGED` – Filesystem change under cwd (Shiny only)

- `CONFIG_CHANGE` – settings file change (Shiny only)

The following Claude Code events are defined for parity but have no live
trigger in codeagent (they never fire); see the inline notes:

- `ELICITATION` / `ELICITATION_RESULT` – need MCP elicitation (mcptools
  lacks it)

- `TEAMMATE_IDLE` – codeagent teams are one-shot mirai workers (no idle
  state)

- `SETUP` – no init/maintenance lifecycle phase

- `CWD_CHANGED` – no run-time cwd-change behaviour
