# Context compaction controller

Monitors token usage and dispatches the appropriate compaction level.
Includes a circuit breaker that silences compaction after 3 consecutive
failures to prevent infinite compaction loops.

## Methods

### Public methods

- [`CompactionController$adaptive_compact()`](#method-CompactionController-adaptive_compact)

- [`CompactionController$maybe_compact()`](#method-CompactionController-maybe_compact)

- [`CompactionController$compact_now()`](#method-CompactionController-compact_now)

- [`CompactionController$handle_ptl_error()`](#method-CompactionController-handle_ptl_error)

- [`CompactionController$reset_failures()`](#method-CompactionController-reset_failures)

- [`CompactionController$failure_count()`](#method-CompactionController-failure_count)

- [`CompactionController$clone()`](#method-CompactionController-clone)

------------------------------------------------------------------------

### `CompactionController$adaptive_compact()`

Run adaptive compaction with circuit-breaker protection.

#### Usage

    CompactionController$adaptive_compact(
      chat,
      settings = list(),
      model = "",
      compact_model = .HAIKU_MODEL,
      request_turns = NULL,
      full_enabled = FALSE,
      force_summary = FALSE,
      hooks = NULL,
      use_provider_usage = TRUE
    )

#### Arguments

- `chat`:

  An [`ellmer::Chat`](https://ellmer.tidyverse.org/reference/Chat.html)
  object.

- `settings`:

  Named compaction settings.

- `model`:

  Character. Active request model.

- `compact_model`:

  Character. Model for summary tasks.

- `request_turns`:

  Optional complete outgoing request including pending.

- `full_enabled`:

  Whether summary escalation is allowed.

- `force_summary`:

  Whether to summarize even after cheap reduction.

- `hooks`:

  Optional lifecycle registry; receives sanitized metadata only.

- `use_provider_usage`:

  Whether initial accounting may include prior usage.

#### Returns

A sanitized internal compaction decision.

------------------------------------------------------------------------

### `CompactionController$maybe_compact()`

Check token usage and compact if needed.

#### Usage

    CompactionController$maybe_compact(
      chat,
      model_limit = 200000L,
      compact_model = .HAIKU_MODEL,
      model = "",
      hooks = NULL,
      use_provider_usage = TRUE
    )

#### Arguments

- `chat`:

  An [`ellmer::Chat`](https://ellmer.tidyverse.org/reference/Chat.html)
  object.

- `model_limit`:

  Integer. Raw model context-window token limit.

- `compact_model`:

  Character. Model for compaction tasks.

- `model`:

  Character. Active request model used to resolve output reserve.

- `hooks`:

  Optional lifecycle registry.

- `use_provider_usage`:

  Whether initial accounting may include prior usage.

#### Returns

Invisibly the internal compaction decision, or NULL when disabled.

------------------------------------------------------------------------

### `CompactionController$compact_now()`

Force the adaptive summary chain for manual compaction.

#### Usage

    CompactionController$compact_now(chat, compact_model = .HAIKU_MODEL)

#### Arguments

- `chat`:

  An [`ellmer::Chat`](https://ellmer.tidyverse.org/reference/Chat.html)
  object.

- `compact_model`:

  Character. Model for compaction tasks.

#### Returns

Invisibly TRUE on a validated change, FALSE otherwise. The structured
decision is attached as a `decision` attribute.

------------------------------------------------------------------------

### `CompactionController$handle_ptl_error()`

Handle a prompt-too-long (PTL) error by dropping turns.

#### Usage

    CompactionController$handle_ptl_error(chat, error = NULL, pending_turn = NULL)

#### Arguments

- `chat`:

  An [`ellmer::Chat`](https://ellmer.tidyverse.org/reference/Chat.html)
  object.

- `error`:

  An error condition or message string (parsed for a real context limit
  when present).

- `pending_turn`:

  Optional failed outgoing pending turn.

------------------------------------------------------------------------

### `CompactionController$reset_failures()`

Reset the failure counter (e.g. after a successful turn).

#### Usage

    CompactionController$reset_failures()

------------------------------------------------------------------------

### `CompactionController$failure_count()`

Return current failure count.

#### Usage

    CompactionController$failure_count()

------------------------------------------------------------------------

### `CompactionController$clone()`

The objects of this class are cloneable with this method.

#### Usage

    CompactionController$clone(deep = FALSE)

#### Arguments

- `deep`:

  Whether to make a deep clone.
