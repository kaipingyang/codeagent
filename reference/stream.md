# Agent streaming API

Public streaming primitives for codeagent. These run the full per-turn
pipeline (compaction, system-reminder injection, session save, cost
tracking) and expose typed callbacks for each content event.

- [`codeagent_stream_async()`](https://kaipingyang.github.io/codeagent/reference/codeagent_stream_async.md)
  — returns a
  [`coro::async`](https://coro.r-lib.org/reference/async.html) promise.
  Use this inside Shiny `ExtendedTask` bodies or any
  [`coro::async`](https://coro.r-lib.org/reference/async.html) context.

- [`codeagent_stream()`](https://kaipingyang.github.io/codeagent/reference/codeagent_stream.md)
  — synchronous wrapper that pumps the event loop with
  [`later::run_now()`](https://later.r-lib.org/reference/run_now.html)
  and handles `Ctrl+C` gracefully. Use in CLI/ink.
