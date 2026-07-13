# Stream one agent turn asynchronously

Runs the full turn pipeline (compaction, system-reminder injection,
session save, cost tracking) and invokes typed callbacks for each
content event.

## Usage

``` r
codeagent_stream_async(
  client,
  input,
  on_delta = NULL,
  on_thinking = NULL,
  on_tool_request = NULL,
  on_tool_result = NULL,
  on_error = NULL,
  on_usage = NULL,
  controller = NULL,
  tool_mode = "concurrent",
  session_id = NULL,
  iteration = 1L,
  cwd = NULL,
  compaction_ctrl = NULL,
  resource_state = NULL
)
```

## Arguments

  - client:
    
    A `CodeagentClient` (from `codeagent_client()`) or a bare
    `ellmer::Chat` object (or any list with a `$stream_async` method for
    testing via duck-typing).

  - input:
    
    Character scalar. The user message.

  - on\_delta:
    
    Optional `function(text_chunk)`. Called for each text chunk.

  - on\_thinking:
    
    Optional `function(text)`. Called for thinking blocks (only on
    models with extended thinking enabled).

  - on\_tool\_request:
    
    Optional `function(list(id, name, arguments, intent))`. Called from
    the `ContentToolRequest` stream chunk, **before** the permission
    gate. Useful for displaying a "pending" tool card.

  - on\_tool\_result:
    
    Optional `function(list(id, name, display, value, is_error))`.
    Called from the `ContentToolResult` stream chunk. `display` is a
    typed toolcard contract from
    [tool\_display](https://kaipingyang.github.io/codeagent/reference/tool_display.md)
    suitable for rich rendering.

  - on\_error:
    
    Optional `function(message, recovered)`. Called on error.

  - on\_usage:
    
    Optional `function(usage)`. Called at turn end with a list:
    `n_tokens`, `model_limit`, `warning_state`, `cost_last` (USD or
    `NA`).

  - controller:
    
    Optional `ellmer::stream_controller()` for cancellation.

  - tool\_mode:
    
    `"concurrent"` (default) or `"sequential"`. Passed to
    `chat$stream_async(tool_mode=)`. Concurrent mode only accelerates
    asynchronous tools; synchronous CLI tools execute serially
    regardless.

  - session\_id:
    
    Character or NULL. Passed to `save_session()`.

  - iteration:
    
    Integer. Current turn iteration (affects system-reminder injection
    and memory recall on iteration 1).

  - cwd:
    
    Character or NULL. Working directory.

  - compaction\_ctrl:
    
    A `CompactionController` or NULL.

  - resource\_state:
    
    A `ContentReplacementState` or NULL.

## Value

A `coro::async` promise resolving to `list(text, usage, stop_reason)`
where `stop_reason` is one of `"completed"`, `"error"`, or
`"interrupted"`.

## Details

**Tool event dual paths** (see plan §6 for details):

  - `on_tool_request` / `on_tool_result` parameters are called from the
    `ContentToolRequest` / `ContentToolResult` **stream chunks**.
    `on_tool_request` fires **before** the permission gate ("pre-gate
    notification"). `on_tool_result` receives a typed `display` contract
    from `.adapt_tool_result()`.

  - `chat$on_tool_request` / `chat$on_tool_result` **callbacks**
    (registered by the permission gate, midloop compaction, and display
    helpers) are independent and complementary.

## See also

`codeagent_stream()` for the synchronous wrapper.
