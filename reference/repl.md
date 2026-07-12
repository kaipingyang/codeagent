# Interactive CLI REPL (harness, no Shiny)

A terminal read-eval-print loop for the agent. Reuses one
`CodeagentClient` so history accumulates in the Chat object across
turns. Mirrors the Shiny
[`agent_loop()`](https://github.com/kaipingyang/codeagent/reference/agent_loop.md)
turn pipeline so long sessions stay healthy: per-turn compaction,
`<system-reminder>` injection, skill preprocessing, and auto-save – the
same harness objects the app uses.

Slash commands: `/model`, `/compact`, `/clear`, `/sessions`, `/budget`,
`/help`, `/exit`. `/<skill>` invokes a skill via
[`load_skill_prompt()`](https://github.com/kaipingyang/codeagent/reference/load_skill_prompt.md).
The line parser `.repl_dispatch()` is a pure function (testable); the
loop
[`codeagent_console()`](https://github.com/kaipingyang/codeagent/reference/codeagent_console.md)
handles IO + the turn pipeline.
