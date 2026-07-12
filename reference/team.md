# Multi-Agent Team Coordination

Run several independent sub-agent tasks in parallel and collect their
results, mirroring Claude Code's team / parallel-agent dispatch. This
uses the `mirai` package (CRAN) for parallel execution across background
daemons – we do not reimplement a scheduler. Each task runs a
self-contained codeagent query in its own daemon, so the tasks must be
independent (no shared mutable state). Results are returned in input
order.

For dependent / interactive multi-agent work prefer the serial
`agent_tool` (sub-agent) path;
[`team_run()`](https://github.com/kaipingyang/codeagent/reference/team_run.md)
is for embarrassingly-parallel fan-out (e.g. "review these 5 files",
"research these 3 questions").
