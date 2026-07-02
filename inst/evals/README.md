# codeagent LLM Evaluation Suite

This directory contains [vitals](https://vitals.tidyverse.org) evaluation
tasks for codeagent. Run these to measure agent quality before/after:

- Changing the system prompt (`R/prompts.R`)
- Switching models (`CODEAGENT_MODEL`)
- Modifying tools or permissions

## Quick start

```r
# Set up your client first
source("inst/evals/setup_eval_client.R")

# Run all evals
source("inst/evals/eval.R")
```

## Task files

| File | What it tests |
|------|---------------|
| `tasks/tool_use.R` | Agent correctly uses Read/Bash/Glob tools |
| `tasks/permissions.R` | Permission modes (plan=deny writes, bypass=allow) |
| `tasks/data_explore.R` | ExploreData tool: schema + query + isolation |
| `tasks/skill_trigger.R` | Skills invoked correctly via /name |

## Viewing results

```r
vitals::vitals_view()  # opens Inspect log viewer in browser
```
