# Agent streaming API

Public streaming primitives for codeagent. These run the full per-turn
pipeline (compaction, system-reminder injection, session save, cost
tracking) and expose typed callbacks for each content event.

  - `codeagent_stream_async()` — returns a `coro::async` promise. Use
    this inside Shiny `ExtendedTask` bodies or any `coro::async`
    context.

  - `codeagent_stream()` — synchronous wrapper that pumps the event loop
    with `later::run_now()` and handles `Ctrl+C` gracefully. Use in
    CLI/ink.
