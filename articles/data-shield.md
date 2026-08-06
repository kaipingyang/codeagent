# Data Shield: strict data-safety mode (design preview)

> **Status — P0/P0.5/P1/P1.5/C2/C5-policy available; fuller design in
> progress.** The egress row-cap, protected-value matching, strict
> DescribeData, ordered scanners, universal pre-tool ingress, per-tool
> policy, promise-backed egress approval, portable path/symlink sandbox,
> and optional sanitized-code reviewer are wired. Full OS execution
> adapter and `distributions="on"/"dp"` remain roadmap. Off by default
> (`data_shield = NULL`).

## Why

When codeagent is embedded as a backend over **sensitive data**
(clinical, financial, PII), the guarantee we want is: the LLM may see
**metadata and descriptive summaries**, but **never raw row-level
data**. Data Shield is an **opt-in, pluggable valve** that enforces this
— off by default (`data_shield = NULL`), composed from independent
strategies when on.

## The core: two edges

Strip away the agent machinery and data can reach the LLM through **only
two inbound edges**. Guard both and you have guarded everything:

1.  **Prompt / system-prompt content** — including the framework’s own
    **ambient-context auto-injection** (codeagent can inject a summary
    of R session objects into the system reminder). This is the part we
    control and must keep **schema-only** (names / types / dimensions),
    never values.
2.  **Tool results** — whatever a tool returns and that is fed back to
    the model.

Everything else reduces to these two (RAG and errors arrive as one of
them; model-generated content is outbound, not inbound). The guarantee
applies **recursively to sub-agents** — each has its own two edges.

> Blind spot to handle separately: an **image/multimodal** tool result
> (a rendered table/plot of raw rows) bypasses text scanning.

## Design: composable strategies (not a fixed mode)

`data_shield` accepts `NULL` (off), an ordered strategy list (creates
one private `DataShield` R6), or an explicit `DataShield` instance (for
upload and intentional session/thread sharing). Implemented strategies
are shown first; planned strategies are listed separately so the
examples never imply they already exist.

``` r

# Implemented now:
client <- codeagent_client(..., data_shield = list(
  shield_describe(k_anon = 5),
  shield_egress(detectors = c("row_cap", "value_match"),
                max_rows = 0, on_fail = "block"),
  shield_regex(on_fail = "redact"),
  shield_ingress(langs = c("r", "python", "bash"), on_fail = "ask"),
  shield_tool_policy(rules = list(
    KMPlot = list(ingress = "scan", egress = "bypass"),
    DangerousExport = list(execution = "deny")
  )),
  shield_sandbox(project_root = getwd(), backend = "policy"),
  shield_reviewer(model = Sys.getenv("CODEAGENT_FAST_MODEL"),
                  scope = c("exec", "write", "net"), on_risk = "ask")
))

# Roadmap (not implemented yet):
# shield_narrow_tools()
```

The main boundary is **edge 2 (tool results)**; sandbox, ingress
blacklist, reviewer, and tool narrowing are defense-in-depth, not the
boundary.

## Current parameter reference

### `data_shield` input

| Value | Effect |
|----|----|
| `NULL` | Shield completely off; existing codeagent behaviour unchanged |
| `list(shield_*())` | Strategies run in list order; codeagent creates one private `DataShield` R6 for this client |
| `DataShield$new(...)` | Explicit lifecycle for uploads and deliberate sharing among selected chats |

### `shield_egress()` — core tool-result boundary

| Parameter | Default | Actual effect |
|----|----|----|
| `detectors` | `c("row_cap", "value_match")` | `row_cap` catches bulk tabular output; `value_match` catches indexed high-entropy values |
| `max_rows` | `0` | On a bulk/tabular match, retain zero raw printed lines and return only a withheld/blocked notice. `5` would deliberately expose the first five printed lines |
| `on_fail` | `"redact"` | `redact`: withheld notice; `block`: blocked notice; `ask`: pause before LLM delivery |
| `allow_raw_approval` | `FALSE` | When asking, show only Redact/Block; TRUE adds dangerous Raw once |
| `approval_timeout` | `60` | Async seconds before automatic redact |

`max_rows = 0` does **not** block
[`print()`](https://rdrr.io/r/base/print.html) generally.
`print(nrow(df))`, status messages, model summaries, plots, and errors
pass unless another detector finds sensitive content. It triggers only
when output has a data.frame/tibble or many-line rectangular-table
shape.

With `on_fail="ask"`, the raw result remains local while the callback/UI
receives only tool name/id, strategy, reason label, match count, score,
timeout and whether raw-once is enabled. Redact is the safe default for
no callback, errors, invalid choices, ESC and timeout. Raw-once applies
to one result only and is audited.

### `shield_describe()` — strict model-safe metadata

| Parameter | Default | Actual effect |
|----|----|----|
| `distributions` | `"off"` | Implemented strict mode: no histograms, quantiles, means, category counts, rows, or free-text examples. `on`/`dp` are roadmap and fail explicitly |
| `k_anon` | `5` | Category labels supported by fewer than k rows become `<rare suppressed>` |
| `category_max` | `20` | Maximum distinct character values for categorical treatment |
| `category_ratio` | `0.2` | Maximum distinct/non-missing ratio for character-categorical treatment; otherwise `free_text` |

Sensitivity still clamps output: `identifier`/`quasi` values stay
suppressed; `measure`/`open` may show numeric/date min–max and safe
category labels without counts.

### `shield_regex()` — unregistered PII/secrets

| Parameter | Default | Actual effect |
|----|----|----|
| `patterns` | `NULL` | Optional named regular-expression rules using PCRE (Perl-Compatible Regular Expression) syntax, e.g. `c(study_id = "STUDY-[0-9]+")`; appended to defaults when enabled |
| `include_defaults` | `TRUE` | Email, phone-like, common-token-prefix, and 18-character identity-number rules |
| `replacement` | `"[REDACTED]"` | Marker inserted once per merged matching span |
| `on_fail` | `"redact"` | `redact`: preserve safe surrounding text; `block`: replace the whole result |
| `ignore_case` | `TRUE` | Case-insensitive matching for all rules |

### `shield_ingress()` — scan every tool call before execution

| Parameter | Default | Actual effect |
|----|----|----|
| `langs` | `c("r", "python", "bash")` | Select built-in rules for each code/shell language |
| `patterns` | `NULL` | Named regex rules; a name matching a built-in **replaces** that rule, a new name is **added**. Host file-based blacklists read their own file into a named vector and pass it here |
| `include_defaults` | `TRUE` | Include the built-in per-language rule set (`.DATA_SHIELD_INGRESS_RULES`): serialization/encoding, pandas/R writers, network transfer (incl. `nc`/`scp`/`/dev/tcp`), data-file display, and protected-name preview |
| `on_fail` | `"block"` | `block`: reject the tool call; `ask`: force the existing permission approval UI/callback |
| `ignore_case` | `TRUE` | Case-insensitive matching |

Ingress scans **all** tool arguments before the usual read/write/exec
capability fast paths, including unknown and read-only tools. It does
not ban ordinary reading: defaults focus on high-confidence
read-and-display, serialization, encoding, and network-transfer
patterns. It is a cheap pre-filter; egress scanning remains the primary
boundary because code can be obfuscated.

### `shield_tool_policy()` — exact/glob trust and deny rules

| Setting | Meaning |
|----|----|
| `default="scan"` | Every tool is scanned unless a rule overrides it |
| `execution="deny"` | Reject the tool before execution |
| `ingress="bypass"` | Skip Shield argument scanning, but still apply permission gate |
| `egress="bypass"` | Return that tool’s output without Shield filtering; audit every bypass |
| `egress="deny"` | Replace the result with an explicit policy-denied notice |

Rules support exact names and `*` globs. Exact wins; otherwise the first
matching glob wins. For example, `KMPlot` may bypass egress when its
developer guarantees all outputs are LLM-safe, while `btw_tool_docs_*`
can receive a broader trusted rule. This policy never bypasses
codeagent’s independent permission system.

### `shield_sandbox()` — portable containment without crippling the agent

| Parameter | Default | Actual effect |
|----|----|----|
| `project_root` | [`getwd()`](https://rdrr.io/r/base/getwd.html) | Project root allowed by path policy |
| `protected_paths` | none | Extra registered data roots; longest matching root controls mode |
| `temp_root` | new session temp | Isolated temporary root |
| `modes` | project `rwx`, data `rw`, temp `rwx` | Logical Shield capabilities (not chmod bits) |
| `process_exec` | `TRUE` | Preserve RunR/Bash/Python; FALSE blocks exec tools |
| `network` | `"tool_policy"` | Let tool policy decide; `"deny"` blocks net capability |
| `symlink_escape` | `"deny"` | Resolve real paths and reject links escaping allowed roots |
| `backend` | `"auto"` | `policy`, `auto`, or `required` |
| `on_unavailable` | `"policy"` | Full OS adapter unavailable → policy fallback; `block` fails closed for exec/net |

Current implementation is a portable central-gate path/capability
policy. It is not advertised as kernel isolation: the capability probe
found user/network/ mount namespaces but no bubblewrap/container, and
plain `unshare` still sees the host filesystem. A future full adapter
must move exec tools out of process.

### `shield_reviewer()` — optional sanitized-code semantic rail

| Parameter | Default | Actual effect |
|----|----|----|
| `client_factory` | `NULL` | Optional function returning a fresh independent ellmer Chat |
| `model` | `CODEAGENT_FAST_MODEL` | Reviewer model; missing config follows `on_error`, never silently main model |
| `scope` | exec/write/net | Only these tool capabilities incur review cost |
| `on_risk` | `"ask"` | Risk classification becomes ask or block |
| `on_error` | `"ask"` | Missing model, timeout, request/JSON errors become ask or block; no approval→block |
| `backend` | `"remote_sanitized"` | Remote sees only regex/value-sanitized code; raw egress review is local-only roadmap |
| `timeout` | `30` | Async review timeout seconds |

The reviewer is not a tool and cannot be skipped by the main model. It
has no tools or history; code is delimited as untrusted data and parsed
from fixed JSON (`risk`, `confidence`, `reason`). Deterministic ingress
rules run first, so already-blocked calls incur no model cost.

### `DataShield$new()` direct lifecycle

Direct constructor parameters (`max_rows`, `distributions`, `k_anon`,
`category_max`, `category_ratio`, `audit_max`) create the default
DescribeData + core egress configuration when `strategies = NULL`.
`audit_max` defaults to 1000 non-sensitive decision events; `0` disables
recording. Supplying `strategies = list(...)` enables **only** listed
strategies and preserves list order. Use `shield$register_data()`,
`$install()`, `$describe()`, `$audit()`, `$clear_audit()`, `$clear()`,
and `$close()` for dynamic/session-owned workflows.

## Plain-language glossary

| Term | Plain meaning |
|----|----|
| **ingress** | A tool call’s name/arguments entering local execution; scanned before the tool runs |
| **egress** | Content leaving a local tool and about to enter the LLM |
| **row-cap** | A limit on how many printed table lines may pass; `0` means no raw line |
| **value-match** | Exact matching against high-entropy values indexed from registered protected data |
| **PII** | Personally identifiable information, such as email, phone, identity number, or name |
| **kind** | What a registered asset is (dataset/spec/document/synthetic), not its R data type or access level |
| **provenance** | A verifiable source tag showing which registered asset produced a result |
| **raw access** | Content may enter an LLM edge without row/value restrictions; optional secret/PII scanning may still apply |
| **regex** | Regular expression: a text pattern such as `STUDY-[0-9]+` |
| **PCRE** | Perl-Compatible Regular Expression, the regex syntax used by R with `perl=TRUE` |
| **span** | Start/end character positions of a detected sensitive substring, enabling precise replacement |
| **k-anonymity threshold** | Do not expose a category label unless at least `k` rows support it |
| **fail closed** | If a safety scanner fails, block output instead of allowing it |
| **semantic reviewer** | A separate small model that classifies what sanitized tool code is trying to do; it never sees raw data remotely |
| **R6** | R’s mutable object system; one `DataShield` owns private datasets/index/lifecycle |

## Non-sensitive audit log

`shield$audit()` returns an in-memory data.frame of policy decisions:

| Field | Meaning |
|----|----|
| `timestamp` | UTC event time |
| `edge` | `ingress` (before tool) or `egress` (before LLM) |
| `tool_name`, `tool_call_id` | Non-sensitive correlation identifiers |
| `strategy` | `row_cap`, `value_match`, `regex`, `ingress`, or custom scanner name |
| `action`, `reason` | `redact`/`block`/`ask` and a rule/reason label |
| `match_count`, `score` | Number of matches and normalized risk score |

It **never stores** raw tool arguments/results, matched values, data
rows, span text, or hashes. `audit_max` bounds memory (oldest events are
dropped); use `shield$clear_audit()` to clear it. Each `DataShield` R6
has its own log, so session/thread isolation matches the policy
instance.

``` r

recent <- shield$audit(limit=100)
shield$clear_audit()
```

## Data Asset Policy: what it is × what the LLM may see

Asset content type and LLM access are orthogonal:

| `kind` | Default prompt | Default egress | Typical use |
|----|----|----|----|
| `dataset` | `schema` | `scan` | patient/analysis data |
| `spec` | `raw` | `scan` | ADaM spec, SDTMIG, public dictionaries |
| `synthetic` | `raw` | `scan` | dummy/edge-case test data |
| `document` | `scan` | `scan` | ordinary reference documents |

| Access | Meaning |
|----|----|
| `none` | content unavailable to that LLM edge |
| `schema` | only strict DescribeData-style metadata |
| `scan` | content must pass configured Shield scanners |
| `raw` | bypass row/value restrictions; baseline secret/PII regex still applies unless explicitly disabled |

``` r

shield$register_asset(
  adam_spec,
  name = "adam_spec",
  kind = "spec",
  llm_access = list(prompt = "raw", egress = "scan"),
  scan_secrets = TRUE,
  reason = "Validated public specification",
  expires = "session"
)

prompt_text <- shield$prompt_content("adam_spec")
```

Raw egress never follows from `kind` alone. It requires explicit policy
and provenance:

``` r

shield$register_asset(
  adam_spec, name = "adam_spec", kind = "spec",
  llm_access = list(prompt = "raw", egress = "raw"),
  reason = "Validated public specification")

tool_result <- shield$trusted_result(value, source = "adam_spec")
```

An untagged or mixed tool result remains scanned. Raw asset policies
require a reason, expire with the owning DataShield session by default,
may set a POSIXct expiry, and emit bypass audit events. Synthetic raw
always keeps baseline PII/secret scanning; spec raw may explicitly set
`scan_secrets = FALSE`.

### Column-level raw access

Assets are whole-object; `register_data(column_access=)` is the
column-grained counterpart for a protected data.frame that contains a
few public-dictionary columns (e.g. an SDTM `TESTCD` codelist) alongside
protected ones. It reuses the same `none`/`schema`/`scan`/`raw` access
levels as assets, split into `prompt`/`egress`, and a raw edge likewise
requires a non-empty `reason`.

``` r

shield$register_data(
  vs, name = "vs",
  sensitivity   = c(SUBJID = "identifier", TESTCD = "identifier"),
  column_access = list(
    TESTCD = list(prompt = "raw", egress = "raw",
                  reason = "SDTM public codelist", scan_secrets = TRUE)))
```

- `prompt = "raw"` lets `DescribeData` enumerate that column’s real
  values (no k-anonymity suppression) so the model can write correct
  filters.
- `egress = "raw"` removes the column from the value-match index, so its
  values are not withheld from tool output.
- An override **missing its `reason` is dropped with a warning**, and
  the column falls back to its sensitivity tier — a mislabeled column
  fails safe, never silently leaks. `coverage()$raw_access_columns`
  counts active overrides.

### Host pattern: a provenance-tagging spec tool

Raw asset egress needs a provenance tag. Rather than a framework
“trusted tool” type, a host composes the existing primitives —
`register_asset()` plus `trusted_result()` — inside its own tool:

``` r

read_adam_spec_tool <- function(shield) {
  ellmer::tool(
    name = "ReadADaMSpec",
    fun = function(path) {
      text <- readLines(path, warn = FALSE)
      shield$trusted_result(paste(text, collapse = "\n"), source = "adam_spec")
    },
    description = "Read a registered, LLM-safe ADaM specification.",
    arguments = list(path = ellmer::type_string("Spec file path")))
}
# register once; the tool auto-tags provenance on every read
shield$register_asset(adam_spec_path, name = "adam_spec", kind = "spec",
  llm_access = list(prompt = "raw", egress = "raw"),
  reason = "Validated public specification")
```

The agent calls `ReadADaMSpec` like any tool; the raw bypass is
authorized by the registered asset policy and audited, and a
mixed/untagged result from any other tool is still scanned.

## P0 — the foundation (available now)

The minimal, deterministic slice that already gives real protection:

``` r

# Easy entry: strategy specs create one private DataShield R6 for this client.
client <- codeagent_client(chat, data_shield = list(
  shield_describe(k_anon = 5),

  shield_egress(max_rows = 0)
))

# Harness-only client: attach tools, then install its R6 engine.
client <- codeagent_client(chat, register_tools = FALSE,
  data_shield = list(shield_describe(), shield_egress(max_rows = 0)))
chat$register_tool(my_tool)
client$data_shield$install(client$chat)
```

- **Edge 2 — shape-based egress row-cap.** codeagent does **not**
  inspect code or block `print`. It looks only at the **shape** of a
  tool’s returned text: output with a data.frame / tibble print
  signature or a many-row rectangular table is truncated to a shape
  summary; scalars, messages, **model summaries**, plots and errors pass
  through untouched. Content-agnostic and tunable via `max_rows`.
- **Edge 1 — ambient stays schema-only.** codeagent’s ambient injection
  already emits only `name [data.frame N x M: col:type, ...]` (no
  values); Data Shield keeps it that way.

### Runtime uploads in Shiny

The dataset does **not** need to be known when the app starts. Register
it in the upload observer immediately after reading it; tools may
already be attached and wrapped, because value matching reads the live
index at invocation time.

``` r

# Inside each Shiny server session: one R6 may be shared by selected chats.
shield <- DataShield$new(
  strategies = list(shield_describe(), shield_egress(max_rows = 0)))
data_env <- new.env(parent = emptyenv())

client_factory <- function() {
  codeagent_client(make_chat(), data_shield = shield)
}

observeEvent(input$file, {
  df <- read.csv(input$file$datapath)
  data_env$uploaded <- df
  shield$register_data(df, name = "uploaded") # no advance columns needed
})
```

A complete runnable host-style Shiny example is installed at:

``` r

system.file("examples/data_shield_upload_app.R", package = "codeagent")
```

From a development checkout:

``` r

devtools::load_all(".")
source("inst/examples/data_shield_upload_app.R")
```

It demonstrates five outcomes after upload: bulk rows withheld by
`row_cap`, a single indexed value withheld by `value_match`,
unregistered PII redacted by `shield_regex`, a harmless shape summary
passed through, and strict `DescribeData` metadata with raw identifiers
suppressed.

For a smaller single-focus demo — a real `codeagent_client` wired into a
real
[`shinychat::chat_ui`](https://posit-dev.github.io/shinychat/r/reference/chat_ui.html),
with `fileInput()` upload on one side and the live non-sensitive audit
log on the other — see `inst/examples/data_shield_minimal_app.R`.

> **Multi-user isolation:** create `DataShield$new()` inside the Shiny
> server function, share it only among the intended chat threads, and
> register data via `shield$register_data()`. Other browser sessions
> receive separate R6 instances and cannot see or influence its index.

Illustrative behaviour of the P0 row-cap (implemented):

| tool output                             | P0 action              |
|-----------------------------------------|------------------------|
| `print(mtcars)` (bulk rows)             | capped → shape summary |
| a tibble print (`# A tibble: 320 x 12`) | capped                 |
| `print(nrow(df))` → `320`               | passes                 |
| a status message                        | passes                 |
| `print(summary(fit))`                   | passes (not row data)  |

## P1 `DescribeData`: strict safe metadata contract

`DescribeData` is the sanctioned way for the model to understand
protected data without receiving rows. Its output is determined by three
orthogonal dimensions:

| Dimension | Values | Purpose |
|----|----|----|
| Global policy | `distributions = "off" / "on" / "dp"` | strict defaults to no distributions; `on` is explicit opt-in; `dp` adds noise + budget |
| Column sensitivity | `identifier / quasi / measure / open` | business role that clamps the maximum disclosure for that column |
| Data type | numeric / factor / character / Date / … | determines the safe representation: range, labels, or free-text marker |

Strict (`distributions = "off"`) matrix:

| Metadata | identifier / quasi | measure / open |
|----|----|----|
| column name, type, missing presence | shown | shown |
| numeric/date min–max | hidden | shown |
| low-cardinality categorical labels | hidden | shown without counts; levels with support `< k` are suppressed |
| real free-text examples | hidden | hidden |
| histogram, quantiles, mean/SD, category counts | hidden | hidden (`on`/`dp` opt-in only) |

A factor is not automatically safe: a factorised subject ID remains an
`identifier`. Character columns receive categorical labels only when
they are low-cardinality, low-uniqueness, non-PII, and every exposed
level satisfies the k-anonymity threshold. Free text never receives real
examples in strict mode.

## P1.5 ordered egress scanners

Strategy-list order is the execution order.
[`shield_regex()`](https://kaipingyang.github.io/codeagent/reference/shield_regex.md)
catches sensitive content even when no data.frame was registered:

``` r

client <- codeagent_client(chat, data_shield=list(
  shield_egress(max_rows=0),
  shield_regex(on_fail="redact"),
  shield_regex(patterns=c(study_id="STUDY-[0-9]+"),
               include_defaults=FALSE, on_fail="block")
))
```

Built-ins cover email, phone-like strings, common API-token prefixes and
18-character identity-number shapes. `redact` replaces only matched
spans; `block` discards the whole model-facing result. Custom scanner
functions may be appended with `shield$add_scanner(name, fn)`; invalid
scanner results/errors fail closed.

## C2 universal ingress scanning

[`shield_ingress()`](https://kaipingyang.github.io/codeagent/reference/shield_ingress.md)
is installed into codeagent’s existing single central permission gate;
it does not create a competing callback/gate. It scans every tool’s
arguments before the read-only fast path. A `block` result raises
`tool_reject`; an `ask` result reuses the current CLI/Shiny approval
callback, including tool-call id correlation.

``` r

client <- codeagent_client(chat, data_shield=list(
  shield_ingress(on_fail="ask"),
  shield_egress(max_rows=0),
  shield_regex()
))
```

Defaults intentionally do not reject every `Read` or `print`:
`nrow(study)` and `print("done")` pass, while `head(study)`,
`dput(study)`, base64/pickle/JSON serialization, upload-style
curl/requests calls, and shell display of data files are reviewed or
blocked.

## C5 portable sandbox and btw boundary

[`shield_sandbox()`](https://kaipingyang.github.io/codeagent/reference/shield_sandbox.md)
deliberately preserves coding capability: project and session-temp
default to `rwx`, protected data defaults to `rw` but may be `rwx`, and
process execution stays enabled. Its current portable backend blocks
explicit paths outside allowed roots, rejects symlink escape, and
applies network/process capability policy in the central gate.

btw is not assumed to provide OS isolation. Its file tools enforce cwd
with
[`fs::path_has_parent()`](https://fs.r-lib.org/reference/path_math.html)
but a project-internal symlink to an external file passed our probe; its
RunR executes through `evaluate` in the global environment and only
restores cwd/options/envvars. Data Shield therefore applies uniformly to
native, btw, MCP and host tools.

## C4 semantic reviewer

[`shield_reviewer()`](https://kaipingyang.github.io/codeagent/reference/shield_reviewer.md)
supplements deterministic ingress rules for indirect aliases, multi-step
serialization and obfuscated source-to-sink intent. Remote reviewers
receive only sanitized code and non-value metadata. A fresh independent
Chat is created per review, with no tools/history. The default factory
uses the parent provider plus `CODEAGENT_FAST_MODEL`; an explicit
`client_factory` may provide a local or specialized reviewer.
Missing/failed/invalid reviewers follow `on_error`; ask falls back to
block when no approval channel exists.

## Roadmap

- **P0.5 — `value_match` (available)**: deterministically catches
  *targeted* leaks the row-cap lets through (e.g. printing one patient’s
  name), by matching tool output against high-entropy values registered
  with `shield$register_data()`.
- **P1 — `DescribeData` + protected-data registry (strict available)**:
  the model’s sanctioned hardened view (schema, sensitivity, missing
  presence, measure/open ranges and k-supported labels; no
  distributions/counts/examples). `distributions="on"/"dp"` remain later
  phases.
- **P1.5 — ordered scanner pipeline +
  [`shield_regex()`](https://kaipingyang.github.io/codeagent/reference/shield_regex.md)
  (available)**: unregistered PII/secrets are redacted/blocked with
  precise spans; custom scanner failures fail closed.
- **C2 —
  [`shield_ingress()`](https://kaipingyang.github.io/codeagent/reference/shield_ingress.md)
  (available)**: all tool arguments pass the central permission gate;
  deterministic high-confidence rules block or force approval.
- **C5 — portable
  [`shield_sandbox()`](https://kaipingyang.github.io/codeagent/reference/shield_sandbox.md)
  (available)**: project/temp `rwx`, protected data `rw` by default,
  realpath/symlink containment and policy fallback; full OS process
  adapter remains roadmap.
- **C4 —
  [`shield_reviewer()`](https://kaipingyang.github.io/codeagent/reference/shield_reviewer.md)
  (available)**: optional sanitized ingress-code semantic rail using a
  fresh small-model Chat; remote raw output remains forbidden.
- **P2 — full OS sandbox adapter and differential privacy for
  distributions (opt-in).**

## Sub-agent boundary

Foreground sub-agents (`Agent`) inherit the exact same `DataShield` R6
before any of their tools can return content to the child model. This
applies to both synchronous and concurrent async Agent calls. While a
shield is active, codeagent deliberately skips btw/custom-agent
delegation paths that cannot accept the policy engine.

`BackgroundAgent` and `/bg` currently **fail closed** under Data Shield:
their mirai worker is a separate R process and cannot safely share the
session’s R6 state or protected-value index. Use foreground `Agent`
until a per-owner worker reconstruction protocol is implemented.

## Combination safety: what each combination actually protects against

Data Shield is composed from independent strategies, so it is possible
to enable a combination that *looks* protective but is not. The table
below is sourced directly from
`tests/testthat/test-data-shield-combinations.R` (a CI suite, not
prose): a future refactor that breaks any of these conclusions fails
that suite immediately, rather than silently drifting out of date.

| Combination | Bulk dump | Targeted single value | Alias bypass (`y <- study; print(y)`) | Verdict |
|----|:--:|:--:|:--:|----|
| [`shield_egress()`](https://kaipingyang.github.io/codeagent/reference/shield_egress.md) alone | withheld | withheld | withheld (egress inspects output content, not the code path) | ✅ safe floor |
| `egress` + `ingress` + `regex` (recommended) | withheld | withheld | withheld | ✅ recommended |
| **[`shield_ingress()`](https://kaipingyang.github.io/codeagent/reference/shield_ingress.md) alone** | **leaks** | **leaks** | **leaks (confirmed)** | ⚠️ **not safe alone** |
| **[`shield_describe()`](https://kaipingyang.github.io/codeagent/reference/shield_describe.md) alone** | **leaks** | **leaks** | — | ⚠️ **not safe alone** (only governs the model’s own metadata query; does not filter other tools’ output) |
| [`shield_regex()`](https://kaipingyang.github.io/codeagent/reference/shield_regex.md) alone | — | leaks for non-PII-shaped custom ids | — | ⚠️ only catches common PII shapes |

**The one-line takeaway:
[`shield_egress()`](https://kaipingyang.github.io/codeagent/reference/shield_egress.md)
is the only non-optional boundary. Every other strategy is
defense-in-depth and cannot substitute for it.**

### Three ready-to-use combination templates

``` r

# Strict: compliance / leadership demos
strict <- list(
  shield_describe(k_anon = 5),
  shield_egress(detectors = c("row_cap", "value_match"), max_rows = 0, on_fail = "block"),
  shield_regex(on_fail = "block"),
  shield_ingress(on_fail = "block"))

# Balanced: everyday development, low friction
balanced <- list(
  shield_egress(max_rows = 0, on_fail = "redact"),
  shield_regex(on_fail = "redact"))

# Clinical: adds the semantic reviewer + strict k-anonymity
clinical <- list(
  shield_describe(k_anon = 5),
  shield_egress(max_rows = 0),
  shield_regex(),
  shield_ingress(on_fail = "ask"),
  shield_reviewer(model = Sys.getenv("CODEAGENT_FAST_MODEL"), on_risk = "ask"))
```

`inst/examples/data_shield_minimal_app.R` has a live “Shield strength”
selector covering these plus the two intentionally UNSAFE combos above,
so you can switch between them in a running chat and watch the exact
leaks in the table happen live.

## Honest limits

Data Shield **reduces** disclosure risk; it does not eliminate it.
Deterministic detectors (row-cap, `value_match`, regex) miss
adversarially obfuscated egress (e.g. base64-encoding data before
printing); those are mitigated — not solved — by the ingress blacklist
and the no-network sandbox. The strongest guarantees come from the
structural layers (metadata-only feeding + no-network execution), with
scanning as defense-in-depth.

Specific residual risks to weigh before relying on it:

- **Layer composition matters — see the combination-safety table
  above.** Enabling only
  [`shield_ingress()`](https://kaipingyang.github.io/codeagent/reference/shield_ingress.md)
  or only
  [`shield_describe()`](https://kaipingyang.github.io/codeagent/reference/shield_describe.md)
  without
  [`shield_egress()`](https://kaipingyang.github.io/codeagent/reference/shield_egress.md)
  is **not** a safe configuration. Do not omit egress.
- **The semantic reviewer is itself an LLM.**
  [`shield_reviewer()`](https://kaipingyang.github.io/codeagent/reference/shield_reviewer.md)
  can be evaded by a sufficiently obfuscated source-to-sink path and
  adds latency/cost per reviewed call; it is defense-in-depth over the
  deterministic rails, not a guarantee.
- **`value_match` scales linearly and is now bounded.** Benchmarked on
  CDISC ADaM data (`inst/bench/value_match_benchmark.R`): ~130 MB of
  keys and ~10 s to index 1M high-entropy values, with zero false
  positives on ordinary clinical prose and real `USUBJID`/`SUBJID`
  caught. Because memory grows linearly and unbounded,
  `register_data(max_index_values=)` caps the index (default 500 000,
  ~65 MB); on overflow it warns and the unindexed tail relies on the
  other egress layers. The `min_len`/`min_card` thresholds performed
  well on real ids and are unchanged.
- **Images/multimodal and full OS isolation remain roadmap** (see the
  status banner): a rendered table/plot of raw rows bypasses text
  scanning, and the portable sandbox is a path/capability policy, not
  kernel isolation.
- **`shinychat` file attachments bypass Data Shield entirely.**
  codeagent’s main UI enables `chat_ui(allow_attachments = TRUE)`; a
  user-dragged attachment goes straight into the prompt edge
  (`user_contents`) and is currently **not scanned** by any egress
  layer. This is a known, unfixed gap — distinct from `fileInput()` →
  `register_data()`, which IS a controlled, scanned path. Track before
  relying on attachments with a shield enabled.
