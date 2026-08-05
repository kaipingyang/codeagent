# Configure per-tool/agent Data Shield policy

Override Shield handling by exact tool name or `*` glob. `scan` is the
safe default; `bypass` explicitly skips one Shield edge and is audited;
`deny` prevents execution (or blocks egress). Shield bypass never
bypasses the independent permission gate.

## Usage

``` r
shield_tool_policy(default = "scan", rules = list())
```

## Arguments

- default:

  Default mode (`"scan"`).

- rules:

  Named list keyed by exact/glob tool names. Each rule may contain
  `execution`, `ingress`, and `egress` set to `scan`, `bypass`, or
  `deny`.

## Value

A Data Shield tool-policy strategy specification.

## Examples

``` r
trusted_plot <- shield_tool_policy(rules = list(
  KMPlot = list(ingress = "scan", egress = "bypass"),
  DangerousExport = list(execution = "deny")
))
```
