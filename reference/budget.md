# Token Budget Tracker

BudgetTracker monitors token usage and signals when the agent should
stop. Mirrors Claude Code's budget tracking:

  - `.BUDGET_STOP_RATIO` threshold triggers stop

  - Diminishing-return detection: stop if token growth \<
    `.BUDGET_MIN_GROWTH` for `.BUDGET_MAX_STALL_TURNS` consecutive turns

  - Minimum `.BUDGET_MIN_ITERATIONS` iterations before stopping

  - Sub-agents are exempt from budget constraints
