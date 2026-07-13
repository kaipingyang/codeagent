# Token budget tracker

Token budget tracker

Token budget tracker

## Details

Monitors token consumption and detects when the agent loop should stop
due to context exhaustion or diminishing returns.

## Methods

### Public methods

- [`BudgetTracker$reset()`](#method-BudgetTracker-reset)

- [`BudgetTracker$should_stop()`](#method-BudgetTracker-should_stop)

- [`BudgetTracker$state()`](#method-BudgetTracker-state)

- [`BudgetTracker$clone()`](#method-BudgetTracker-clone)

------------------------------------------------------------------------

### Method `reset()`

Reset the tracker state.

#### Usage

    BudgetTracker$reset()

------------------------------------------------------------------------

### Method `should_stop()`

Determine whether the agent loop should stop.

#### Usage

    BudgetTracker$should_stop(
      current_tokens,
      max_tokens,
      iteration = 1L,
      is_subagent = FALSE
    )

#### Arguments

- `current_tokens`:

  Integer. Current total token count.

- `max_tokens`:

  Integer. Maximum allowed tokens (model context limit).

- `iteration`:

  Integer. Current loop iteration (1-indexed).

- `is_subagent`:

  Logical. If TRUE, budget limits are not applied.

#### Returns

Logical. TRUE if the loop should stop.

------------------------------------------------------------------------

### Method `state()`

Return current tracker state.

#### Usage

    BudgetTracker$state()

#### Returns

Named list with `prev_tokens` and `same_count`.

------------------------------------------------------------------------

### Method `clone()`

The objects of this class are cloneable with this method.

#### Usage

    BudgetTracker$clone(deep = FALSE)

#### Arguments

- `deep`:

  Whether to make a deep clone.
