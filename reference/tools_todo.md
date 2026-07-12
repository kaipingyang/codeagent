# TodoWrite Tool

A single tool that lets the model maintain a persistent markdown TODO
list for the current session, mirroring Claude Code's TodoWrite. Unlike
the in-memory `TaskCreate`/`TaskList` tools (`tools_task.R`), the todo
list is written to `~/.codeagent/todos/<session>.md` so it survives
across turns and sessions and is human-readable on disk.
