# Run a set of independent tasks as a parallel agent team

Run a set of independent tasks as a parallel agent team

## Usage

``` r
team_run(
  tasks,
  model = NULL,
  n_workers = NULL,
  permission_mode = "bypass",
  cwd = getwd()
)
```

## Arguments

  - tasks:
    
    Character vector of task prompts (one sub-agent per task).

  - model:
    
    Character. Model spec each agent uses. Defaults to the
    `CODEAGENT_MODEL` env var or `"claude-sonnet-4-6"`.

  - n\_workers:
    
    Integer or NULL. Number of parallel daemons. Defaults to
    `min(length(tasks), parallelly::availableCores())` so it never
    exceeds the container's cgroup CPU quota (each daemon is a heavy R
    process).

  - permission\_mode:
    
    Character. Permission mode for each agent (default `"bypass"` since
    parallel agents cannot prompt interactively).

  - cwd:
    
    Character. Working directory for each agent.

## Value

A list (same length/order as `tasks`), each element either the agent's
text result or an `[Error] ...` string.
