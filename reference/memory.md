# Auto-Memory (persistent agent memory)

File-based persistent memory under `~/.codeagent/memory/`. The agent
writes durable facts via the `remember` tool; relevant memories are
injected back into each turn's `<system-reminder>` so they survive
across sessions. Mirrors Claude Code's auto-memory layer.

Layout:

  - `~/.codeagent/memory/<slug>.md` – one fact per file, optional YAML
    front-matter (`name`, `description`).

  - `~/.codeagent/memory/MEMORY.md` – a one-line-per-memory index loaded
    into context each session.
