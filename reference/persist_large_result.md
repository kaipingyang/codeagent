# Persist a large tool result to disk (Layer 2)

If `content` exceeds `.L2_PERSIST_THRESHOLD` characters, writes it to
`~/.codeagent/tool-results/<tool_id>.txt` and returns a short preview
plus the path. Small results are returned unchanged.

## Usage

``` r
persist_large_result(content, tool_id)
```

## Arguments

  - content:
    
    Character(1). Tool output.

  - tool\_id:
    
    Character(1). Unique identifier for this tool call.

## Value

Character(1). Possibly shortened content with path reference.
