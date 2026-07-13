# System Prompt Sections

Behavioural guidance for the agent, written for codeagent's R context.
Each `.prompt_*()` returns a markdown section string (or "" to skip).
They are assembled by `.build_system_prompt()` in `settings.R`.

Design: these are constant text (no side effects, no `Sys.time()`), so
the prompt is stable and prompt-cache friendly. Per-turn ephemeral
context (date / iteration / cwd) lives in `.build_system_reminder()`
instead.

The built-in tool names referenced here (Bash/Read/Write/Edit/MultiEdit/
Glob/Grep/LS, and the task/skill/agent tools) are codeagent's own tool
registry names; R-specific conventions are added in
`.prompt_r_specifics()`.
