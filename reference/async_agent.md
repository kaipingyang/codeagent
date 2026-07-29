# Background (non-blocking) sub-agents

Fire-and-forget sub-agents that run in a `mirai` daemon so the main REPL
/ turn continues immediately (unlike
[`team_run()`](https://kaipingyang.github.io/codeagent/reference/team_run.md),
which waits). Results are polled and surfaced back to the model on a
later turn via the system reminder – mirroring Claude Code's async
agents (`createAsyncAgentAttachmentsIfNeeded`). Opt-in via
`settings$background_agents`; requires the `mirai` package.
