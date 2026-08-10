# Build the AuditCode tool (pluggable static code-safety auditor)

Wraps the deterministic audit pipeline
([`.audit_code_impl()`](https://kaipingyang.github.io/codeagent/reference/dot-audit_code_impl.md))
as an
[`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html) the
main-loop model can call to check whether a block of R code safely
references external scripts/data before running it. The tool NEVER gives
the model (or the reviewer) a read/write/shell capability: it
deterministically extracts referenced paths (AST), enforces an
in-project source-file whitelist in code, reads only whitelisted files,
and (with a shield) hands the vetted text to the reviewer.

## Usage

``` r
audit_code_tool(shield = NULL, project_root = getwd())
```

## Arguments

- shield:

  Optional `DataShield` whose reviewer reviews referenced file contents
  (`NULL` = report references only).

- project_root:

  Directory the read whitelist is confined to.

## Value

An [`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html).

## Details

Opt-in: not registered by default. Host wires it in (e.g. when running
with the sandbox disabled) so the model can self-audit external
references.
