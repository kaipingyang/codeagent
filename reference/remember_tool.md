# Create the `remember` tool

Lets the agent persist a durable fact to auto-memory. Read-only-ish
(writes only to the memory dir), so it is not permission-gated.

## Usage

``` r
remember_tool()
```

## Value

An `ellmer::tool()` object.
