# Data Shield: strict data-safety mode (design preview)

> **Status — P0/P0.5/P1-strict available; fuller design in progress.**
> The egress row-cap, per-session protected-value matching, and strict
> `DescribeData` safe metadata tool are wired. `DescribeData` exposes no
> distributions/counts by default; only sensitivity-gated ranges and
> k-supported category labels. The fuller strategy API (`shield_egress`
> actions/reviewer/sandbox and `distributions="on"/"dp"`) remains
> roadmap. Off by default (`data_shield = NULL`).

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

`data_shield` is `NULL` (off) or a **list of independent strategies**
you compose freely. The execution model borrows llm-guard’s scanner
pipeline (ordered, `fail_fast`, each returns
`sanitized / valid / score / action`); the per-strategy `on_fail` action
and named registry borrow from guardrails-ai. All pure R — no Python.

``` r

# Target API (in progress):
codeagent_client(..., data_shield = list(
  shield_describe(k_anon = 5),                                  # safe metadata only
  shield_egress(detectors = c("value_match", "regex"),          # main boundary
                max_rows = 0, on_fail = "block"),
  shield_ingress(langs = c("R", "python", "bash"), on_fail = "ask"),
  shield_reviewer(model = "<a small, fast model>", scope = "exec"), # small-model audit
  shield_sandbox(no_network = TRUE),                            # OS confinement
  shield_narrow_tools()
))
```

The main boundary is **edge 2 (tool results)**; the rest (sandbox,
ingress blacklist, reviewer, tool narrowing) are **defense-in-depth**,
not the boundary.

## P0 — the foundation (available now)

The minimal, deterministic slice that already gives real protection:

``` r

# Simple one-chat use: config list creates a private state for this client.
client <- codeagent_client(chat, data_shield = list(max_rows = 0))

# Harness-only client: install after attaching your own tools.
client <- codeagent_client(chat, register_tools = FALSE,
                           data_shield = list(max_rows = 0))
chat$register_tool(my_tool)
install_data_shield(client)
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

# Inside each Shiny server session: one state may be shared by multiple chats.
shield <- data_shield(max_rows = 0)
data_env <- new.env(parent = emptyenv())

client_factory <- function() {
  codeagent_client(make_chat(), data_shield = shield)
}

observeEvent(input$file, {
  df <- read.csv(input$file$datapath)
  data_env$uploaded <- df
  register_protected_data(df, shield = shield) # no advance columns needed
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

It demonstrates four outcomes after upload: bulk rows withheld by
`row_cap`, a single indexed value withheld by `value_match`, a harmless
shape summary passed through, and strict `DescribeData` metadata with
raw identifiers suppressed.

> **Multi-user isolation:**
> [`data_shield()`](https://kaipingyang.github.io/codeagent/reference/data_shield.md)
> returns a session-scoped state. Create it inside the Shiny server
> function, share it only among that user’s chat threads, and pass it
> explicitly to
> [`register_protected_data()`](https://kaipingyang.github.io/codeagent/reference/register_protected_data.md).
> Other browser sessions receive separate states and cannot see or
> influence its index.

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
examples in strict mode. \## Roadmap

- **P0.5 — `value_match` (available)**: deterministically catches
  *targeted* leaks the row-cap lets through (e.g. printing one patient’s
  name), by matching tool output against high-entropy values registered
  with
  [`register_protected_data()`](https://kaipingyang.github.io/codeagent/reference/register_protected_data.md).
- **P1 — `DescribeData` + protected-data registry (strict available)**:
  the model’s sanctioned hardened view (schema, sensitivity, missing
  presence, measure/open ranges and k-supported labels; no
  distributions/counts/examples). `distributions="on"/"dp"` remain later
  phases.
- **P2 — reviewer (small model), sandbox (folder + no-network),
  differential privacy for distributions (opt-in).**

## Honest limits

Data Shield **reduces** disclosure risk; it does not eliminate it.
Deterministic detectors (row-cap, `value_match`, regex) miss
adversarially obfuscated egress (e.g. base64-encoding data before
printing); those are mitigated — not solved — by the ingress blacklist
and the no-network sandbox. The strongest guarantees come from the
structural layers (metadata-only feeding + no-network execution), with
scanning as defense-in-depth.
