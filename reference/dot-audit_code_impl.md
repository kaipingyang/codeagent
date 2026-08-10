# Audit R code for risky external references (deterministic pipeline).

Runs the full first-pass audit: AST extraction -\> tool-layer path
whitelist -\> deterministic read of whitelisted source files -\>
(optionally) feed the read text to the Data Shield reviewer. The
reviewer NEVER gets a read/write/shell tool: this function decides what
to read (code, not LLM), bounds it to whitelisted in-project source
files, and only hands the reviewer vetted text.

## Usage

``` r
.audit_code_impl(
  code,
  shield = NULL,
  project_root = getwd(),
  max_bytes = 100000L
)
```

## Arguments

- code:

  Character. The R code to audit (untrusted; parsed, not run).

- shield:

  Optional `DataShield` whose reviewer reviews the referenced file
  contents. `NULL` -\> report references only (no content review).

- project_root:

  Directory the whitelist confines reads to.

- max_bytes:

  Per-file read cap (avoid feeding huge files to the reviewer).

## Value

A list: `static_paths`, `dynamic`, `allowed` (paths read), `blocked`
(list of path+reason not read), `reviews` (per-file reviewer verdicts
when a shield is given), `risk` (overall: "none"/"review"/"block").
