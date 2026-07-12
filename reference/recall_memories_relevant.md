# Recall only the memories relevant to a query (haiku-selected)

Improves on
[`recall_memories()`](https://github.com/kaipingyang/codeagent/reference/recall_memories.md)
(which concatenates everything) by asking a small/fast model to pick the
memories relevant to the current user query – Claude Code's sideQuery
memory-selection pattern. Falls back to the full concatenation when
there is no query, the fast model is unavailable, or selection fails, so
behaviour never regresses.

## Usage

``` r
recall_memories_relevant(query = NULL, max_memories = 5L, model = .HAIKU_MODEL)
```

## Arguments

- query:

  Character or NULL. The current user message. NULL -\> full recall.

- max_memories:

  Integer. Max memories to include after selection.

- model:

  Character. Small/fast model for selection (default `.HAIKU_MODEL`).

## Value

Character. A recall block, or "" if there are no memories.
