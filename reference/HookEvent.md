# Hook event types

Named list of lifecycle event names that can be hooked.

## Usage

``` r
HookEvent
```

## Format

An object of class `list` of length 12.

## Details

- `PRE_TOOL_USE` – Before tool execution (can allow/deny/modify input)

- `POST_TOOL_USE` – After successful tool execution (can modify output)

- `POST_TOOL_USE_FAILURE` – After a tool throws an error

- `PERMISSION_DENIED` – When a tool call is blocked by permissions

- `PERMISSION_REQUEST` – When permission mode is "ask" (bubble/default)

- `USER_MESSAGE` – When user sends a message to the agent

- `ASSISTANT_MESSAGE` – When the assistant produces a text response
