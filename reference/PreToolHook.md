# Pre-tool hook definition

Pre-tool hook definition

## Usage

``` r
PreToolHook(fn, tool_pattern = NULL, timeout_ms = 2000L)
```

## Arguments

- fn:

  Function. `function(tool_name, tool_input)` -\> list with `action`
  (`"allow"`, `"deny"`, `"updated_input"`) and optional fields.

- tool_pattern:

  Character or NULL. Regex pattern to match tool names. `NULL` matches
  all tools.

- timeout_ms:

  Integer. Timeout in milliseconds (default 2000).

## Value

Object of class `PreToolHook`.
