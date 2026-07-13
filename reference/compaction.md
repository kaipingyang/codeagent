# Context Compaction System

Four-level context compaction mirroring Claude Code's design.

  - L1 MicroCompact/Snip: replace old tool results with a placeholder

  - L2 Session Memory: incremental summary (10K-40K tokens retained)

  - L3 Full Compaction: fork agent generates a 9-section structured
    summary

  - L4 PTL Fallback: drop oldest turns on 413/prompt\_too\_long errors

Trigger threshold: `model_limit - 20000 - 13000` tokens (e.g. 167K for
200K model). Circuit breaker: 3 consecutive failures silence further
compaction attempts.
