# Agent Sub-agent Tool

Sub-agent delegation tools. Uses btw's hierarchical subagent system when
available (`btw_tool_agent_subagent`); falls back to codeagent's own
simple sub-agent loop.

Also discovers and registers custom agent definitions from:

- `.btw/agent-*.md` (project)

- `~/.btw/agent-*.md` (user)

- `.claude/agents/` (Claude Code compat)
