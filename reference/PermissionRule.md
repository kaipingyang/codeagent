# Create a permission rule

Create a permission rule

## Usage

``` r
PermissionRule(
  tool_name,
  behavior = c("allow", "deny", "ask"),
  source = "session",
  rule_content = NULL
)
```

## Arguments

- tool_name:

  Character. Tool name pattern (supports `*` wildcard).

- behavior:

  Character. One of `"allow"`, `"deny"`, `"ask"`.

- source:

  Character. Rule source for priority ordering.

- rule_content:

  Character or NULL. Fine-grained condition (e.g. `"npm test:*"`).

## Value

Object of class `PermissionRule`.
