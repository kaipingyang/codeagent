# Configure a small-model semantic code reviewer

Add an internal (non-tool) ingress rail that reviews only
deterministically sanitized code/arguments. The reviewer receives no raw
data or raw tool output, has no tools/history, and returns a fixed JSON
risk classification.

## Usage

``` r
shield_reviewer(
  client_factory = NULL,
  model = Sys.getenv("CODEAGENT_FAST_MODEL", ""),
  scope = c("exec", "write", "net"),
  on_risk = c("ask", "block"),
  on_error = c("ask", "block"),
  backend = c("remote_sanitized", "local_only"),
  timeout = 30
)
```

## Arguments

- client_factory:

  Optional function returning a fresh ellmer Chat. When NULL, codeagent
  binds a factory using the parent provider and `model`.

- model:

  Reviewer model id; defaults to `CODEAGENT_FAST_MODEL`. Missing model
  is handled by `on_error` and never silently falls back to main model.

- scope:

  Tool capabilities to review (default exec/write/net).

- on_risk, on_error:

  `"ask"` or `"block"`.

- backend:

  `"remote_sanitized"` or `"local_only"`. Raw content is never passed in
  remote mode; egress review remains a later local-only feature.

- timeout:

  Async review timeout seconds.

## Value

A Data Shield reviewer strategy specification.
