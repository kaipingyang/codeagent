# Create the WebFetch tool

Fetches an authorized public HTTP(S) URL directly. DNS answers are
validated and the selected public IP is pinned for the connection;
redirects are re-authorized one hop at a time.

## Usage

``` r
web_fetch_tool(citations = FALSE)
```

## Arguments

- citations:

  Logical. Append the source-ID marker protocol to model-facing output.
  Source metadata is always retained in the tool result.

## Value

An [`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html)
object.
