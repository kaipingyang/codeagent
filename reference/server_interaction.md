# Shiny interaction pause mechanism (Phase 3)

Shared "pause -\> wait for user -\> resume" machinery for two features
that ride the same promise-as-pause-signal design:

- **ask_fn** – harness permission approval (Allow/Deny a risky tool).

- **ask_question_fn** – `AskUserQuestion` clarifying-question input.

Both store a single `state$pending_interaction` slot and expose an
interaction bar in the chat footer. The promise returned by the ask
functions is awaited by the (async) tool inside the streaming task; it
is resolved by the Allow/Deny/Submit observers here.

Hard-won constraints (see `inst/examples/test_shiny_ask_fn.R`):

- The promise is ONLY a container for `resolve`; never use `then()` to
  do UI side effects (then() runs with a NULL reactive domain).

- All UI side effects happen inside the Allow/Deny/Submit observers,
  which run in the correct reactive domain.

## Usage

``` r
server_interaction(input, output, session, state)
```

## Arguments

- input, output, session:

  Standard Shiny server args.

- state:

  The shared `reactiveValues` (must contain `pending_interaction`).

## Value

A list with `ask_fn` and `ask_question_fn` (promise-returning).
