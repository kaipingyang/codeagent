# Context management and compaction

codeagent keeps long conversations within the model’s context window
using an automatic, Claude Code-aligned compaction strategy.

## Dynamic context window

The context window is resolved from the model rather than hard-coded.
Resolution order (highest priority first):

1.  `CODEAGENT_MAX_CONTEXT_TOKENS` environment variable.
2.  A `[1m]` suffix in the model name (forces a 1,000,000-token window).
3.  A built-in capability table (claude / gpt / gemini / deepseek / …),
    or a provider-reported window when available.
4.  A 200,000-token default.

``` r

# The effective window reserves output tokens; the auto-compaction threshold
# sits one buffer below that (e.g. ~167K for a 200K Claude model).
```

## When compaction triggers

Compaction runs when the estimated token usage crosses the
auto-compaction threshold
(`effective window - output reserve - buffer`). Token usage prefers the
*real* usage from the last API exchange (`Chat$get_tokens()`), falling
back to a character estimate.

## Two-level flow

1.  **Snip** old tool results (cheap pre-step).
2.  **Session-memory compaction** — an incremental summary of the
    earliest turns.
3.  **Full compaction** — a single 9-section structured summary
    (verbatim Claude Code prompt) replacing the conversation, used when
    session-memory can’t run.

A circuit breaker stops auto-compaction after repeated failures, and a
413 / prompt-too-long error triggers a reactive fallback that drops the
oldest turns (parsing the real context limit from the error when
present).

## Compaction flow

    token count = Chat$get_tokens() (real usage)  else char/3.5 estimate

    TIER 1 -- turn boundary, before each chat$chat()   [maybe_compact()]
      tokens >= model_limit - 33K margin ?
        | yes           (circuit breaker: stop after 3 consecutive failures)
        v  compact_now()
      snip_old_tools()               clear old tool results (cheap, no LLM)
        v
      session_memory_compact()   L1: incremental summary of the earliest turns
        | did not run (too few turns)
        v
      full_compact()             L2: one 9-section structured summary replaces history

    TIER 2 -- between tool rounds, on ellmer on_tool_result  [.midloop_compact_step()]
      settings$midloop_compact (default ON) AND tokens >= midloop_trigger ?
        +- default:  snip_old_tools(target_tokens)   budget-aware micro-snip (no LLM)
        +- opt-in (settings$midloop_full_compact):    compact_now()  (same L1 -> L2)

    REACTIVE -- on send error 413 / prompt_too_long   [ptl_fallback()]
        drop oldest turns until under the parsed real limit, then retry chat$chat() once

The mid-loop step currently rides ellmer’s `on_tool_result` (fires
between tool rounds); the cleaner upstream target is `on_turn_start`
(ellmer PR \#1052).

## Context-left indicator

Both the REPL banner and the Shiny status bar show “N% context left”,
turning yellow near the warning line and red near the error/blocking
line
([`calculate_token_warning_state()`](https://github.com/kaipingyang/codeagent/reference/calculate_token_warning_state.md)).

## Controls

``` r

Sys.setenv(CODEAGENT_DISABLE_COMPACT = "1")     # disable auto-compaction
Sys.setenv(CODEAGENT_MAX_CONTEXT_TOKENS = "500000")  # override the window
# Manual compaction from the REPL / Shiny:
# /compact
```
