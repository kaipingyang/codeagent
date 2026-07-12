# Run per-turn setup: compaction, resource replacement, system-reminder injection.

Run per-turn setup: compaction, resource replacement, system-reminder
injection.

## Usage

``` r
.turn_setup(
  client,
  input,
  iteration = 1L,
  cwd = NULL,
  compaction_ctrl = NULL,
  resource_state = NULL
)
```

## Arguments

- client:

  A `CodeagentClient` or bare
  [`ellmer::Chat`](https://ellmer.tidyverse.org/reference/Chat.html).

- input:

  Character scalar (CLI/ink) OR list (Shiny: text + attachments).

- iteration:

  Integer. Current loop iteration (1 = first).

- cwd:

  Character or NULL. Working directory.

- compaction_ctrl:

  A `CompactionController` or NULL.

- resource_state:

  A `ContentReplacementState` or NULL.

## Value

`input` with system-reminder injected (same type as input).
