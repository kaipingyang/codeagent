# Multi-agent team coordination

## Overview

codeagent supports running multiple independent sub-agents in parallel
for tasks that can be divided and executed concurrently.

## Coordination at a glance

    team_run(tasks)                    FIXED FAN-OUT (worker i = task i)
      crew / mirai: run_one(task) = codeagent_client() + codeagent(task)
      -> collect results in order

    team_coordinate(tasks, blocked_by)   WORK-STEALING over a SQLite board
      board_create(): tasks + deps (DAG) + messages tables
      seed tasks (add, then wire blocked_by by index) + toposort (reject cycles)
      N workers, each:  repeat {
         board_claim()  -- BEGIN IMMEDIATE: lowest pending id whose blockers are done
            | none claimable
            +- pending == 0            -> all done, break
            +- board_reclaim_stale()   -> reclaim a crashed worker's task
            +- stalled (dead-end)      -> break
            +- else Sys.sleep(backoff) -> retry   (a blocker still running)
         run codeagent(task) -> board_complete(result) -> board_send_message()
      }
      -> board_status() data.frame (id, prompt, owner, status, result)

    team_lead(goal, max_rounds)        LLM-LEAD loop
      decompose (chat_structured -> tasks + DAG)
        -> team_coordinate(...)              (runs the work-stealing board above)
        -> review (chat_structured: done? follow-up tasks?)
        -> replan -> next round              (until done or max_rounds)

## Fixed fan-out: team_run()

[`team_run()`](https://github.com/kaipingyang/codeagent/reference/team_run.md)
assigns one task per worker and collects all results:

``` r

library(codeagent)

# Review multiple files in parallel
results <- team_run(c(
  "Review R/tool_display.R for any issues",
  "Review R/permissions.R for any issues",
  "Review R/compaction.R for any issues"
))

# Each element of results is the agent's response for that task
cat(results[[1]])
```

Worker count defaults to `min(#tasks, parallelly::availableCores())` to
respect container CPU limits.

## Work-stealing: team_coordinate()

[`team_coordinate()`](https://github.com/kaipingyang/codeagent/reference/team_coordinate.md)
uses a shared SQLite task board where workers claim tasks dynamically –
faster workers take more tasks:

``` r

results_df <- team_coordinate(
  tasks = c("task 1", "task 2", "task 3", "task 4", "task 5"),
  n_workers = 2
)
# Returns a data.frame with columns: id, prompt, owner, status, result
print(results_df[, c("prompt", "status", "owner")])
```

### Inter-agent messaging

The shared board also supports messages between agents:

``` r

db <- board_create()
board_add_task(db, "analyse the sales data")
board_add_task(db, "generate the summary report")

# Worker 1 claims a task
task <- board_claim(db, worker_id = "w1")
board_send_message(db, sender = "w1", body = "Starting analysis...",
                   recipient = "coordinator")

# Complete with result
board_complete(db, task$id, result = "Analysis complete: 3 trends found")
```

## Sub-agents in the Shiny app

The agent can invoke sub-agents via the `Agent` tool directly from the
chat. Enable it by registering the agent tool:

``` r

client <- codeagent_client(chat,
  permission_mode = "bypass",
  worktree_isolation = TRUE   # each sub-agent in its own git worktree
)
```
