# Concurrent tool execution scheduler

Concurrent tool execution scheduler

Concurrent tool execution scheduler

## Details

Manages parallel execution of concurrent-safe tools while serialising
non-concurrent-safe tools. Mirrors Claude Code's
`StreamingToolExecutor`.

Rules:

- Concurrent-safe tools run immediately (in parallel with other safe
  tools).

- Non-concurrent-safe tools wait for all running tools to finish,
  execute exclusively, then release the queue.

- Tool calls submitted while an unsafe tool is running are queued and
  executed in order when the unsafe tool completes.

## Methods

### Public methods

- [`StreamingToolExecutor$new()`](#method-StreamingToolExecutor-new)

- [`StreamingToolExecutor$submit()`](#method-StreamingToolExecutor-submit)

- [`StreamingToolExecutor$drain_queue()`](#method-StreamingToolExecutor-drain_queue)

- [`StreamingToolExecutor$collect_results()`](#method-StreamingToolExecutor-collect_results)

- [`StreamingToolExecutor$execute_batch()`](#method-StreamingToolExecutor-execute_batch)

- [`StreamingToolExecutor$execute_batch_async()`](#method-StreamingToolExecutor-execute_batch_async)

- [`StreamingToolExecutor$clone()`](#method-StreamingToolExecutor-clone)

------------------------------------------------------------------------

### Method `new()`

Create a new executor.

#### Usage

    StreamingToolExecutor$new()

------------------------------------------------------------------------

### Method `submit()`

Submit a tool call for execution.

#### Usage

    StreamingToolExecutor$submit(tool_call, exec_fn)

#### Arguments

- `tool_call`:

  Named list with `id`, `name`, `input`.

- `exec_fn`:

  Function `(tool_call) -> character`. Executes the tool and returns the
  result string.

#### Returns

Invisibly NULL (result will appear in `collect_results()`).

------------------------------------------------------------------------

### Method `drain_queue()`

Drain the queue for any unsafe tool that was running. Call this after
marking the unsafe tool as complete.

#### Usage

    StreamingToolExecutor$drain_queue()

#### Arguments

- `exec_fn`:

  Function `(tool_call) -> character`. Executor function.

------------------------------------------------------------------------

### Method `collect_results()`

Collect all completed results and reset the accumulator.

#### Usage

    StreamingToolExecutor$collect_results()

#### Returns

List of result objects (each with `id`, `name`, `result`).

------------------------------------------------------------------------

### Method `execute_batch()`

Execute a batch of tool calls, respecting concurrency rules.

#### Usage

    StreamingToolExecutor$execute_batch(tool_calls, exec_fn)

#### Arguments

- `tool_calls`:

  List of tool call objects.

- `exec_fn`:

  Function `(tool_call) -> character`.

#### Returns

List of result objects.

------------------------------------------------------------------------

### Method `execute_batch_async()`

Async variant of `execute_batch()` for use inside
[`coro::async`](https://coro.r-lib.org/reference/async.html) / Shiny
`ExtendedTask` contexts.

Concurrent-safe tools are dispatched as a group via
[`promises::promise_all()`](https://rstudio.github.io/promises/reference/promise_all.html),
so the Shiny event loop can interleave other work while they run. Unsafe
tools execute serially after all safe tools have resolved.

If the `promises` package is not installed the method falls back to
`execute_batch()` and returns the result directly (not wrapped in a
promise); [`coro::await()`](https://coro.r-lib.org/reference/async.html)
handles plain values transparently.

#### Usage

    StreamingToolExecutor$execute_batch_async(tool_calls, exec_fn)

#### Arguments

- `tool_calls`:

  List of tool call objects (each with `id`, `name`, `input`).

- `exec_fn`:

  Function `(tool_call) -> character`. Must be callable from the current
  R process.

#### Returns

A
[`promises::promise`](https://rstudio.github.io/promises/reference/promise.html)
resolving to the same list that `execute_batch()` returns, or that list
directly when `promises` is unavailable.

------------------------------------------------------------------------

### Method `clone()`

The objects of this class are cloneable with this method.

#### Usage

    StreamingToolExecutor$clone(deep = FALSE)

#### Arguments

- `deep`:

  Whether to make a deep clone.
