# Global context budget manager (Layer 3)

Tracks total estimated token usage across all turns and replaces the
largest tool results with a placeholder when the soft ceiling is
exceeded. This mirrors Claude Code's `ContentReplacementState`.

## Methods

### Public methods

- [`ContentReplacementState$new()`](#method-ContentReplacementState-initialize)

- [`ContentReplacementState$freeze()`](#method-ContentReplacementState-freeze)

- [`ContentReplacementState$maybe_replace()`](#method-ContentReplacementState-maybe_replace)

- [`ContentReplacementState$replaced_ids()`](#method-ContentReplacementState-replaced_ids)

- [`ContentReplacementState$reset()`](#method-ContentReplacementState-reset)

- [`ContentReplacementState$clone()`](#method-ContentReplacementState-clone)

------------------------------------------------------------------------

### `ContentReplacementState$new()`

Create a new state object.

#### Usage

    ContentReplacementState$new(soft_ceiling = .RESOURCE_SOFT_CEILING)

#### Arguments

- `soft_ceiling`:

  Integer. Token threshold to trigger replacement.

------------------------------------------------------------------------

### `ContentReplacementState$freeze()`

Freeze a result (exclude it from replacement).

#### Usage

    ContentReplacementState$freeze(tool_use_id)

#### Arguments

- `tool_use_id`:

  Character.

------------------------------------------------------------------------

### `ContentReplacementState$maybe_replace()`

Check usage and replace large old results if over ceiling.

#### Usage

    ContentReplacementState$maybe_replace(chat)

#### Arguments

- `chat`:

  An [`ellmer::Chat`](https://ellmer.tidyverse.org/reference/Chat.html)
  object (modified in place).

#### Returns

Invisibly NULL.

------------------------------------------------------------------------

### `ContentReplacementState$replaced_ids()`

Return IDs of replaced results.

#### Usage

    ContentReplacementState$replaced_ids()

------------------------------------------------------------------------

### `ContentReplacementState$reset()`

Reset state.

#### Usage

    ContentReplacementState$reset()

------------------------------------------------------------------------

### `ContentReplacementState$clone()`

The objects of this class are cloneable with this method.

#### Usage

    ContentReplacementState$clone(deep = FALSE)

#### Arguments

- `deep`:

  Whether to make a deep clone.
