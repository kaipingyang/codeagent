# Task Management Tools

TaskCreate, TaskGet, TaskUpdate, TaskList tools for codeagent. Tasks are
stored in a per-session environment (created fresh per
[`register_task_tools()`](https://github.com/kaipingyang/codeagent/reference/register_task_tools.md)
call) so concurrent agents do not share state.
