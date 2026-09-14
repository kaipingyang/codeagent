# Track permission denials and emit warnings at thresholds

Track permission denials and emit warnings at thresholds

Track permission denials and emit warnings at thresholds

## Details

Mirrors Claude Code's `denialTracking.ts` behaviour:

- 3 consecutive denials -\> warning to reconsider permission mode

- 20 total denials -\> warning to review permission configuration

## Methods

### Public methods

- [`DenialTracker$record_denial()`](#method-DenialTracker-record_denial)

- [`DenialTracker$record_success()`](#method-DenialTracker-record_success)

- [`DenialTracker$counts()`](#method-DenialTracker-counts)

- [`DenialTracker$clone()`](#method-DenialTracker-clone)

------------------------------------------------------------------------

### Method `record_denial()`

Record a denial event.

#### Usage

    DenialTracker$record_denial()

------------------------------------------------------------------------

### Method `record_success()`

Record a successful tool execution (resets consecutive count).

#### Usage

    DenialTracker$record_success()

------------------------------------------------------------------------

### Method `counts()`

Return current counts.

#### Usage

    DenialTracker$counts()

------------------------------------------------------------------------

### Method `clone()`

The objects of this class are cloneable with this method.

#### Usage

    DenialTracker$clone(deep = FALSE)

#### Arguments

- `deep`:

  Whether to make a deep clone.
