# Post-tool hook definition

Post-tool hook definition

## Usage

``` r
PostToolHook(fn, tool_pattern = NULL, timeout_ms = 2000L)
```

## Arguments

  - fn:
    
    Function. `function(tool_name, tool_input, tool_output)` -\> list
    with `action` (`"allow"`, `"updated_output"`) and optional fields.

  - tool\_pattern:
    
    Character or NULL. Regex pattern to match tool names.

  - timeout\_ms:
    
    Integer. Timeout in milliseconds (default 2000).

## Value

Object of class `PostToolHook`.
