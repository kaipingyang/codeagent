# Global context budget manager (Layer 3)

Global context budget manager (Layer 3)

Global context budget manager (Layer 3)

## Details

Tracks total estimated token usage across all turns and replaces the
largest tool results with a placeholder when the soft ceiling is
exceeded. This mirrors Claude Code's `ContentReplacementState`.

## Methods

### Public methods

- [`ContentReplacementState$new()`](#method-ContentReplacementState-new)

- [`ContentReplacementState$freeze()`](#method-ContentReplacementState-freeze)

- [`ContentReplacementState$maybe_replace()`](#method-ContentReplacementState-maybe_replace)

- [`ContentReplacementState$replaced_ids()`](#method-ContentReplacementState-replaced_ids)

- [`ContentReplacementState$reset()`](#method-ContentReplacementState-reset)

- [`ContentReplacementState$clone()`](#method-ContentReplacementState-clone)

------------------------------------------------------------------------

### Method `new()`

Create a new state object.

#### Usage

    ContentReplacementState$new(soft_ceiling = .RESOURCE_SOFT_CEILING)

#### Arguments

- `soft_ceiling`:

  Integer. Token threshold to trigger replacement.

------------------------------------------------------------------------

### Method `freeze()`

Freeze a result (exclude it from replacement).

#### Usage

    ContentReplacementState$freeze(tool_use_id)

#### Arguments

- `tool_use_id`:

  Character.

------------------------------------------------------------------------

### Method `maybe_replace()`

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

### Method `replaced_ids()`

Return IDs of replaced results.

#### Usage

    ContentReplacementState$replaced_ids()

------------------------------------------------------------------------

### Method `reset()`

Reset state.

#### Usage

    ContentReplacementState$reset()

------------------------------------------------------------------------

### Method `clone()`

The objects of this class are cloneable with this method.

#### Usage

    ContentReplacementState$clone(deep = FALSE)

#### Arguments

- `deep`:

  Whether to make a deep clone.
