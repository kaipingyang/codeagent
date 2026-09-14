# Configure portable sandbox policy

Restrict declared tool path arguments to project/protected/session-temp
roots. This is a portable policy guard, not a kernel sandbox: every
non-delegated exec tool fails closed because project configuration,
child processes, filesystem, or network effects cannot be bounded from
path metadata alone. `backend="auto"` currently falls back to this
policy because no full out-of-process OS adapter is implemented;
`on_unavailable="block"` blocks all exec/net tools when the adapter is
absent.

## Usage

``` r
shield_sandbox(
  project_root = getwd(),
  protected_paths = character(),
  temp_root = NULL,
  modes = list(project = "rwx", protected_data = "rw", temp = "rwx"),
  process_exec = TRUE,
  network = c("tool_policy", "deny"),
  symlink_escape = "deny",
  backend = c("auto", "policy", "required"),
  on_unavailable = c("policy", "block")
)
```

## Arguments

- project_root:

  Project root (default current working directory).

- protected_paths:

  Additional protected data roots.

- temp_root:

  Session-specific temporary root; NULL creates one.

- modes:

  Named list using `r`, `rw`, or `rwx` for project, protected_data, and
  temp.

- process_exec:

  Permit shield-preserving Agent/AuditCode delegation (default TRUE).
  Non-delegated exec tools require a real OS backend and fail closed
  under the policy backend.

- network:

  `"tool_policy"` or `"deny"`.

- symlink_escape:

  Currently only `"deny"`.

- backend:

  `"policy"`, `"auto"`, or `"required"`.

- on_unavailable:

  `"policy"` fallback or `"block"` exec/net.

## Value

A Data Shield sandbox strategy specification.
