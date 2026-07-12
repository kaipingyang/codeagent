# Register a codebase retrieval tool on a chat

Builds (or reuses) a codebase store and attaches ragnar's retrieval tool
so the model can semantically search the project. No-op when ragnar is
missing or indexing yields nothing.

## Usage

``` r
register_rag_tool(chat, cwd = getwd(), store = NULL)
```

## Arguments

- chat:

  An [`ellmer::Chat`](https://ellmer.tidyverse.org/reference/Chat.html)
  object.

- cwd:

  Character. Project root.

- store:

  Optional pre-built ragnar store (skips rebuilding).

## Value

Invisibly `chat`.
