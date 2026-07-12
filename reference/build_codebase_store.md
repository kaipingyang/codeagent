# Build (or rebuild) a codebase vector store

Reads matching project files, chunks them, embeds, and writes a ragnar
store with a vector + BM25 index. Returns the connected store, or NULL
if ragnar is unavailable or no files matched.

## Usage

``` r
build_codebase_store(
  cwd = getwd(),
  location = NULL,
  globs = .RAG_DEFAULT_GLOBS,
  overwrite = TRUE
)
```

## Arguments

- cwd:

  Character. Project root.

- location:

  Character. Store path (default `.codeagent/rag.duckdb`).

- globs:

  Character vector of file globs to index.

- overwrite:

  Logical. Recreate the store if it exists.

## Value

A ragnar store object, or NULL.
