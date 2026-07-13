# Interactive CLI REPL (harness, no Shiny)

A terminal read-eval-print loop for the agent. Reuses one
`CodeagentClient` so history accumulates in the Chat object across
turns. Mirrors the Shiny `agent_loop()` turn pipeline so long sessions
stay healthy: per-turn compaction, `<system-reminder>` injection, skill
preprocessing, and auto-save – the same harness objects the app uses.

Slash commands: `/model`, `/compact`, `/clear`, `/sessions`, `/budget`,
`/help`, `/exit`. `/<skill>` invokes a skill via `load_skill_prompt()`.
The line parser `.repl_dispatch()` is a pure function (testable); the
loop `codeagent_console()` handles IO + the turn pipeline.
