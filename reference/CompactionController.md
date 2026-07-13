# Context compaction controller

Context compaction controller

Context compaction controller

## Details

Monitors token usage and dispatches the appropriate compaction level.
Includes a circuit breaker that silences compaction after 3 consecutive
failures to prevent infinite compaction loops.

## Methods

### Public methods

  - [`CompactionController$maybe_compact()`](#method-CompactionController-maybe_compact)

  - [`CompactionController$compact_now()`](#method-CompactionController-compact_now)

  - [`CompactionController$handle_ptl_error()`](#method-CompactionController-handle_ptl_error)

  - [`CompactionController$reset_failures()`](#method-CompactionController-reset_failures)

  - [`CompactionController$failure_count()`](#method-CompactionController-failure_count)

  - [`CompactionController$clone()`](#method-CompactionController-clone)

-----

### Method `maybe_compact()`

Check token usage and compact if needed.

#### Usage

    CompactionController$maybe_compact(
      chat,
      model_limit = 200000L,
      compact_model = .HAIKU_MODEL
    )

#### Arguments

  - `chat`:
    
    An `ellmer::Chat` object.

  - `model_limit`:
    
    Integer. Model context window token limit.

  - `compact_model`:
    
    Character. Model for compaction tasks (haiku).

#### Returns

Invisibly NULL.

-----

### Method `compact_now()`

Run the two-level compaction now (snip -\> session-memory -\> full
9-section), guarded by the circuit breaker. Unlike `maybe_compact()`
this skips the token-threshold check, so callers that have already
decided to compact (e.g. mid-loop) can reuse the exact same Claude
Code-aligned flow.

#### Usage

    CompactionController$compact_now(chat, compact_model = .HAIKU_MODEL)

#### Arguments

  - `chat`:
    
    An `ellmer::Chat` object.

  - `compact_model`:
    
    Character. Model for compaction tasks (haiku).

#### Returns

Invisibly `TRUE` on success, `FALSE` if skipped or failed.

-----

### Method `handle_ptl_error()`

Handle a prompt-too-long (PTL) error by dropping turns.

#### Usage

    CompactionController$handle_ptl_error(chat, error = NULL)

#### Arguments

  - `chat`:
    
    An `ellmer::Chat` object.

  - `error`:
    
    An error condition or message string (parsed for a real context
    limit when present).

-----

### Method `reset_failures()`

Reset the failure counter (e.g. after a successful turn).

#### Usage

    CompactionController$reset_failures()

-----

### Method `failure_count()`

Return current failure count.

#### Usage

    CompactionController$failure_count()

-----

### Method `clone()`

The objects of this class are cloneable with this method.

#### Usage

    CompactionController$clone(deep = FALSE)

#### Arguments

  - `deep`:
    
    Whether to make a deep clone.
