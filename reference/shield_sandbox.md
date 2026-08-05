# Configure portable sandbox policy

Restrict explicit tool path arguments to project/protected/session-temp
roots while preserving project `rwx` and process execution by default.
This is a portable policy guard, not a kernel sandbox. `backend="auto"`
currently falls back to policy because no full out-of-process OS adapter
is implemented; `on_unavailable="block"` can fail closed for exec/net
tools.

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

  Preserve exec-capability tools (default TRUE).

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
