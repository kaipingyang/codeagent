# Normalize any tool result into the typed display contract

Idempotent: if `result@extra$display$toolcard` already exists it is
returned unchanged. Otherwise inspects the result (and btw's
`@extra$contents` Content objects) to classify a kind and build a typed
`ContentToolResult` whose `@value` is preserved for the LLM.

## Usage

``` r
.adapt_tool_result(result)
```

## Arguments

  - result:
    
    An `ellmer::ContentToolResult` (codeagent, RunR, or raw btw).

## Value

A typed `ContentToolResult`.
