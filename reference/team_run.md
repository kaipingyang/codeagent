# Run a set of independent tasks as a parallel agent team

Run a set of independent tasks as a parallel agent team

## Usage

``` r
team_run(
  tasks,
  model = NULL,
  n_workers = NULL,
  permission_mode = "dont_ask",
  cwd = getwd(),
  parent_rules = NULL,
  parent_policy = NULL,
  security_context = NULL
)
```

## Arguments

- tasks:

  Character vector of task prompts (one sub-agent per task).

- model:

  Character. Model spec each agent uses. Defaults to the
  `CODEAGENT_MODEL` env var or `"claude-sonnet-4-6"`.

- n_workers:

  Integer or NULL. Number of parallel daemons. Defaults to
  `min(length(tasks), parallelly::availableCores())` so it never exceeds
  the container's cgroup CPU quota (each daemon is a heavy R process).

- permission_mode:

  Character. Permission mode for each agent (default `"dont_ask"` since
  parallel agents cannot prompt interactively – NOT "bypass", so
  user-defined deny rules are still honoured).

- cwd:

  Character. Working directory for each agent.

- parent_rules:

  List. Permission rules inherited from the parent agent.

- parent_policy:

  List. Tool capability policies inherited from parent.

- security_context:

  Internal immutable parent security snapshot. When supplied it takes
  precedence over the legacy permission arguments.

## Value

A list (same length/order as `tasks`), each element either the agent's
text result or an `[Error] ...` string.
