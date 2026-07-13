# Unified tool permission gate

A single central gate registered via `chat$on_tool_request()` that
governs EVERY tool call (codeagent-native, btw, Format, MCP) uniformly
by tool name – mirroring Claude Code's central tool-execution pipeline.

ellmer already supports a rejectable central hook: `invoke_tools()` runs
`maybe_on_tool_request(request, cb)` which is `tryCatch({cb(request);
NULL}, ellmer_tool_reject = \(e) ContentToolResult(error=...))`; a
non-NULL result makes the loop skip the tool (`next`). The async loop
does `coro::await(cb(request))` inside the same tryCatch, so a
promise-returning callback can gate the Shiny path too. This gate
therefore replaces the old per-tool embedded checkers (tools built with
`mode = "bypass"`).
