# Data Shield: strict data-safety mode (design preview)

> **Status — P0/P0.5/P1/P1.5 available; fuller design in progress.** The
> egress row-cap, protected-value matching, strict `DescribeData`, and
> ordered regex/custom scanner pipeline are wired. `DescribeData`
> exposes no distributions/counts by default;
> [`shield_regex()`](https://kaipingyang.github.io/codeagent/reference/shield_regex.md)
> covers unregistered PII/secrets. Reviewer/sandbox, ingress scanning,
> and `distributions="on"/"dp"` remain roadmap. Off by default
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
  shield_regex(on_fail = "redact")
))

# Roadmap (not implemented yet):
# shield_ingress(...), shield_reviewer(...), shield_sandbox(...),
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
| `on_fail` | `"redact"` | `redact`: withheld notice; `block`: blocked notice. Neither asks a user yet |

`max_rows = 0` does **not** block
[`print()`](https://rdrr.io/r/base/print.html) generally.
`print(nrow(df))`, status messages, model summaries, plots, and errors
pass unless another detector finds sensitive content. It triggers only
when output has a data.frame/tibble or many-line rectangular-table
shape.

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

### `DataShield$new()` direct lifecycle

Direct constructor parameters (`max_rows`, `distributions`, `k_anon`,
`category_max`, `category_ratio`) create the default DescribeData + core
egress configuration when `strategies = NULL`. Supplying
`strategies = list(...)` enables **only** listed strategies and
preserves list order. Use `shield$register_data()`, `$install()`,
`$describe()`, `$clear()`, and `$close()` for dynamic/session-owned
workflows.

## Plain-language glossary

| Term | Plain meaning |
|----|----|
| **egress** | Content leaving a local tool and about to enter the LLM |
| **row-cap** | A limit on how many printed table lines may pass; `0` means no raw line |
| **value-match** | Exact matching against high-entropy values indexed from registered protected data |
| **PII** | Personally identifiable information, such as email, phone, identity number, or name |
| **regex** | Regular expression: a text pattern such as `STUDY-[0-9]+` |
| **PCRE** | Perl-Compatible Regular Expression, the regex syntax used by R with `perl=TRUE` |
| **span** | Start/end character positions of a detected sensitive substring, enabling precise replacement |
| **k-anonymity threshold** | Do not expose a category label unless at least `k` rows support it |
| **fail closed** | If a safety scanner fails, block output instead of allowing it |
| **R6** | R’s mutable object system; one `DataShield` owns private datasets/index/lifecycle |

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

## Sub-agent boundary

Foreground sub-agents (`Agent`) inherit the exact same `DataShield` R6
before any of their tools can return content to the child model. This
applies to both synchronous and concurrent async Agent calls. While a
shield is active, codeagent deliberately skips btw/custom-agent
delegation paths that cannot accept the policy engine.

`BackgroundAgent` and `/bg` currently **fail closed** under Data Shield:
their mirai worker is a separate R process and cannot safely share the
session’s R6 state or protected-value index. Use foreground `Agent`
until a per-owner worker reconstruction protocol is implemented. -
**P1.5 — ordered scanner pipeline +
[`shield_regex()`](https://kaipingyang.github.io/codeagent/reference/shield_regex.md)
(available)**: unregistered PII/secrets are redacted/blocked with
precise spans; custom scanner failures fail closed. - **P2 — reviewer
(small model), sandbox (folder + no-network), differential privacy for
distributions (opt-in).**

## Honest limits

Data Shield **reduces** disclosure risk; it does not eliminate it.
Deterministic detectors (row-cap, `value_match`, regex) miss
adversarially obfuscated egress (e.g. base64-encoding data before
printing); those are mitigated — not solved — by the ingress blacklist
and the no-network sandbox. The strongest guarantees come from the
structural layers (metadata-only feeding + no-network execution), with
scanning as defense-in-depth.
