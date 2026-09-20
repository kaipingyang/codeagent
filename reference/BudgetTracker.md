# Token budget tracker

Monitors token consumption and detects when the agent loop should stop
due to context exhaustion or diminishing returns.

## Methods

### Public methods

- [`BudgetTracker$reset()`](#method-BudgetTracker-reset)

- [`BudgetTracker$should_stop()`](#method-BudgetTracker-should_stop)

- [`BudgetTracker$state()`](#method-BudgetTracker-state)

- [`BudgetTracker$clone()`](#method-BudgetTracker-clone)

------------------------------------------------------------------------

### `BudgetTracker$reset()`

Reset the tracker state.

#### Usage

    BudgetTracker$reset()

------------------------------------------------------------------------

### `BudgetTracker$should_stop()`

Determine whether the agent loop should stop.

#### Usage

    BudgetTracker$should_stop(
      current_tokens,
      max_tokens,
      iteration = 1L,
      is_subagent = FALSE,
      current_cost_usd = NA_real_,
      max_budget_usd = NULL
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

- `current_cost_usd`:

  Numeric or NA. Current session spend in US dollars (e.g. from
  `.current_cost_usd()`); NA when unknown/unpriced.

- `max_budget_usd`:

  Numeric or NULL. Hard dollar cap; NULL disables the check. When set
  and `current_cost_usd` is known, this fires immediately (bypassing
  `iteration`/`.BUDGET_MIN_ITERATIONS`) – a dollar cap is a hard stop,
  not a heuristic.

#### Returns

Logical. TRUE if the loop should stop.

------------------------------------------------------------------------

### `BudgetTracker$state()`

Return current tracker state.

#### Usage

    BudgetTracker$state()

#### Returns

Named list with `prev_tokens` and `same_count`.

------------------------------------------------------------------------

### `BudgetTracker$clone()`

The objects of this class are cloneable with this method.

#### Usage

    BudgetTracker$clone(deep = FALSE)

#### Arguments

- `deep`:

  Whether to make a deep clone.
