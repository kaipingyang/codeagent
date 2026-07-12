# Stream one agent turn synchronously (CLI / ink)

A synchronous wrapper around
[`codeagent_stream_async()`](https://github.com/kaipingyang/codeagent/reference/codeagent_stream_async.md)
that pumps the `later` event loop at 100 ms intervals. Handles `Ctrl+C`
gracefully: the in-progress stream is cancelled via the
`stream_controller` and the REPL / calling code can continue (the
interrupt is **not** re-thrown).

## Usage

``` r
codeagent_stream(
  client,
  input,
  ...,
  controller = NULL,
  session_id = NULL,
  iteration = 1L,
  cwd = NULL,
  compaction_ctrl = NULL,
  resource_state = NULL
)
```

## Arguments

- client:

  A `CodeagentClient` (from
  [`codeagent_client()`](https://github.com/kaipingyang/codeagent/reference/codeagent_client.md))
  or a bare
  [`ellmer::Chat`](https://ellmer.tidyverse.org/reference/Chat.html)
  object (or any list with a `$stream_async` method for testing via
  duck-typing).

- input:

  Character scalar. The user message.

- controller:

  Optional
  [`ellmer::stream_controller()`](https://ellmer.tidyverse.org/reference/stream_controller.html)
  for cancellation.

- session_id:

  Character or NULL. Passed to
  [`save_session()`](https://github.com/kaipingyang/codeagent/reference/save_session.md).

- iteration:

  Integer. Current turn iteration (affects system-reminder injection and
  memory recall on iteration 1).

- cwd:

  Character or NULL. Working directory.

- compaction_ctrl:

  A `CompactionController` or NULL.

- resource_state:

  A `ContentReplacementState` or NULL.

## Value

Invisibly, `list(text, usage, stop_reason)`.

## See also

[`codeagent_stream_async()`](https://github.com/kaipingyang/codeagent/reference/codeagent_stream_async.md)
for the async variant.
