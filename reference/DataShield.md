# Stateful protected-data policy engine

R6 lifecycle owner for protected datasets, deterministic value indexes,
strategy configuration, tool wrapping, and strict `DescribeData`
metadata. Create one instance per Shiny session or thread; explicitly
share an instance only when those chat threads intentionally share the
same protected data.

`codeagent_client(data_shield = list(shield_*()))` is the declarative
convenience path and creates a private `DataShield` internally. Pass an
explicit `DataShield` instance when data must be registered dynamically
or shared across chats. Instances are intentionally non-cloneable;
create a new object for an independent user/thread boundary.

## Methods

### Public methods

- [`DataShield$new()`](#method-DataShield-initialize)

- [`DataShield$register_data()`](#method-DataShield-register_data)

- [`DataShield$register_asset()`](#method-DataShield-register_asset)

- [`DataShield$asset_policy()`](#method-DataShield-asset_policy)

- [`DataShield$tool_policy()`](#method-DataShield-tool_policy)

- [`DataShield$prompt_content()`](#method-DataShield-prompt_content)

- [`DataShield$trusted_result()`](#method-DataShield-trusted_result)

- [`DataShield$install()`](#method-DataShield-install)

- [`DataShield$describe()`](#method-DataShield-describe)

- [`DataShield$schema_block()`](#method-DataShield-schema_block)

- [`DataShield$scan_egress()`](#method-DataShield-scan_egress)

- [`DataShield$scan_ingress()`](#method-DataShield-scan_ingress)

- [`DataShield$scan_tool_args()`](#method-DataShield-scan_tool_args)

- [`DataShield$scan_prompt()`](#method-DataShield-scan_prompt)

- [`DataShield$scan_response()`](#method-DataShield-scan_response)

- [`DataShield$add_scanner()`](#method-DataShield-add_scanner)

- [`DataShield$set_egress_ask()`](#method-DataShield-set_egress_ask)

- [`DataShield$bind_reviewer_factory()`](#method-DataShield-bind_reviewer_factory)

- [`DataShield$audit()`](#method-DataShield-audit)

- [`DataShield$clear_audit()`](#method-DataShield-clear_audit)

- [`DataShield$clear()`](#method-DataShield-clear)

- [`DataShield$close()`](#method-DataShield-close)

- [`DataShield$coverage()`](#method-DataShield-coverage)

------------------------------------------------------------------------

### `DataShield$new()`

Create a Data Shield.

#### Usage

    DataShield$new(
      max_rows = 0L,
      distributions = "off",
      k_anon = 5L,
      category_max = 20L,
      category_ratio = 0.2,
      audit_max = 1000L,
      strategies = NULL
    )

#### Arguments

- `max_rows`:

  Direct `row_cap` value when `strategies = NULL`: `0` exposes no raw
  tabular line; positive values retain that many leading printed lines.

- `distributions`:

  Direct DescribeData policy. Strict `"off"` only is implemented;
  `"on"`/`"dp"` fail explicitly.

- `k_anon`:

  Minimum category support for exposing a label.

- `category_max`:

  Maximum distinct character values treated as a category.

- `category_ratio`:

  Maximum distinct/non-missing ratio for character categorical
  treatment.

- `audit_max`:

  Maximum in-memory non-sensitive decision events retained.

- `strategies`:

  Optional ordered list from
  [`shield_describe()`](https://kaipingyang.github.io/codeagent/reference/shield_describe.md),
  [`shield_egress()`](https://kaipingyang.github.io/codeagent/reference/shield_egress.md),
  [`shield_regex()`](https://kaipingyang.github.io/codeagent/reference/shield_regex.md),
  [`shield_ingress()`](https://kaipingyang.github.io/codeagent/reference/shield_ingress.md),
  and
  [`shield_tool_policy()`](https://kaipingyang.github.io/codeagent/reference/shield_tool_policy.md).
  If supplied, only listed strategies are enabled and list order
  controls egress execution order.

------------------------------------------------------------------------

### `DataShield$register_data()`

Register one protected data.frame.

#### Usage

    DataShield$register_data(
      df,
      name = NULL,
      sensitivity = NULL,
      cols = NULL,
      column_access = NULL,
      min_len = 3L,
      min_card = 8L,
      max_index_values = 500000L
    )

#### Arguments

- `df`:

  A data.frame retained locally; rows are never emitted by
  `DescribeData`.

- `name`:

  Dataset name used by the model-facing `DescribeData` tool.

- `sensitivity`:

  Optional named overrides: `identifier`, `quasi`, `measure`, or `open`.
  Local heuristics classify unspecified columns.

- `cols`:

  Optional explicit value-match columns. Default: columns classified
  `identifier`/`quasi`.

- `column_access`:

  Optional named list of per-column raw-access overrides, each
  `list(prompt=, egress=, reason=, scan_secrets=)` using
  `none`/`schema`/`scan`/`raw`. A raw edge requires a non-empty
  `reason`; overrides missing it are dropped (with a warning) so the
  column falls back to its sensitivity tier. `egress="raw"` removes the
  column from the value-match index; `prompt="raw"` lets `DescribeData`
  enumerate its real values.

- `min_len, min_card`:

  Minimum value length and column cardinality for deterministic value
  indexing (reduces low-entropy false positives).

- `max_index_values`:

  Cap on indexed values (default 500000, ~65MB of keys). On overflow,
  indexing stops and a warning is emitted; unindexed values are not
  caught by value_match and rely on the other egress layers.
  `NULL`/`Inf` disables the cap.

------------------------------------------------------------------------

### `DataShield$register_asset()`

Register a typed data/document/spec asset and its LLM access policy.

#### Usage

    DataShield$register_asset(
      x,
      name,
      kind,
      llm_access = NULL,
      scan_secrets = TRUE,
      reason = NULL,
      expires = "session"
    )

#### Arguments

- `x`:

  Local asset value or path.

- `name`:

  Unique asset name.

- `kind`:

  `dataset`, `spec`, `document`, or `synthetic`.

- `llm_access`:

  NULL for kind defaults, or list(prompt=, egress=) using `none`,
  `schema`, `scan`, or `raw`.

- `scan_secrets`:

  Keep baseline PII/secret regex active for raw access.

- `reason`:

  Required when prompt or egress access is raw.

- `expires`:

  `"session"` or POSIXct expiry.

------------------------------------------------------------------------

### `DataShield$asset_policy()`

Return non-sensitive policy metadata for one registered asset.

#### Usage

    DataShield$asset_policy(name)

------------------------------------------------------------------------

### `DataShield$tool_policy()`

Resolve effective Shield policy for one tool/agent name.

#### Usage

    DataShield$tool_policy(tool_name)

------------------------------------------------------------------------

### `DataShield$prompt_content()`

Return prompt-safe content according to an asset policy.

#### Usage

    DataShield$prompt_content(name)

------------------------------------------------------------------------

### `DataShield$trusted_result()`

Tag one result with registered provenance for raw egress.

#### Usage

    DataShield$trusted_result(value, source)

------------------------------------------------------------------------

### `DataShield$install()`

Install/refresh this shield on an ellmer Chat.

#### Usage

    DataShield$install(chat)

------------------------------------------------------------------------

### `DataShield$describe()`

Return strict safe metadata for a registered dataset.

#### Usage

    DataShield$describe(name = NULL)

------------------------------------------------------------------------

### `DataShield$schema_block()`

Build a system-prompt block listing every registered protected dataset
with its filtered schema (the same per-dataset output `DescribeData`
produces). Reused by the system-prompt builder so the model knows what
protected data exists without calling the tool first. Reads live engine
state, so it reflects the current dataset set (grows as `register_data`
is called). Returns `""` when no dataset is registered or `DescribeData`
is disabled.

#### Usage

    DataShield$schema_block()

------------------------------------------------------------------------

### `DataShield$scan_egress()`

Apply the ordered egress strategy pipeline to a tool result.

#### Usage

    DataShield$scan_egress(result, context = list())

#### Arguments

- `result`:

  Tool return value.

- `context`:

  Optional non-sensitive context (`tool_name`, `tool_call_id`).

------------------------------------------------------------------------

### `DataShield$scan_ingress()`

Scan one tool request before execution.

#### Usage

    DataShield$scan_ingress(
      tool_name,
      input,
      tool_call_id = NULL,
      capability = "read"
    )

#### Arguments

- `tool_name`:

  Model-facing tool name.

- `input`:

  Named list of tool arguments.

- `tool_call_id`:

  Optional non-sensitive tool-call identifier.

- `capability`:

  Tool capability (`read`, `write`, `exec`, or `net`).

#### Returns

List with action (`pass`, `block`, or `ask`), reason, matches and score.

------------------------------------------------------------------------

### `DataShield$scan_tool_args()`

Redact protected values inside a tool's arguments before the tool
executes (ingress rewrite). Complements `scan_ingress` (which decides
pass/block/ask): this scrubs each string argument value in place using
the same detectors as `scan_prompt` (value_match + PII regex), so a
registered value pasted into a tool argument is redacted rather than the
whole call being blocked. Runs in the tool wrapper, after the permission
gate. Non-string arguments are left untouched.

#### Usage

    DataShield$scan_tool_args(args, scanners = c("regex", "value_match"))

#### Arguments

- `args`:

  Named list of tool arguments.

- `scanners`:

  Detector subset (default both).

#### Returns

List: `action` (`"pass"`/`"redact"`), `args` (possibly-redacted).

------------------------------------------------------------------------

### `DataShield$scan_prompt()`

Scan a user prompt BEFORE it reaches the model (edge 1). This is the
Data Shield half of the prompt gate: it detects protected data the user
may have pasted into their message. Unlike egress (which withholds a
whole unsafe tool result), prompt redaction replaces ONLY the matched
values / PII spans and keeps the rest of the user's text – the user's
original wording is otherwise preserved.

Two detectors, both reusing existing machinery:

- value_match: does the prompt contain a REGISTERED protected value
  (e.g. a real USUBJID)? O(1) hash lookup via the value index.

- regex/PII: email / phone / token / id shapes.

#### Usage

    DataShield$scan_prompt(
      text,
      on_fail = c("redact", "block", "ask"),
      on_progress = NULL,
      context = list(),
      scanners = c("regex", "value_match")
    )

#### Arguments

- `text`:

  Character scalar. The raw user prompt.

- `on_fail`:

  `"redact"` (default, replace matches, keep rest), `"block"` (reject
  the whole turn), or `"ask"` (defer to approval).

- `on_progress`:

  Optional `function(list(stage, status, matched, elapsed_ms))` progress
  callback so a UI can show "scanning data safety...". NULL (default) is
  silent and zero-overhead.

- `context`:

  Optional non-sensitive context (e.g. `tool_call_id`, `edge`).
  `context$edge` labels audit events; defaults to `"prompt"` so the
  reusable output-side wrapper (`scan_response`) can pass
  `edge = "response"` to distinguish direction in the audit log.

- `scanners`:

  Character vector selecting which detectors run, a subset of
  `c("regex", "value_match")`. Default runs both (secure-by-default); a
  host may drop one via `settings$data_shield_input_scanners` /
  `data_shield_output_scanners`.

#### Returns

List: `action` (`"pass"`/`"redact"`/`"block"`/`"ask"`), `text` (possibly
redacted prompt), `matches` (count), `score`.

------------------------------------------------------------------------

### `DataShield$scan_response()`

Scan the model's final reply BEFORE it reaches the user (edge 3, the
output gate). Symmetric to `scan_prompt` (edge 1): the model may
reproduce a protected value it inferred from tool output even when the
user's input was clean, so the reply is scanned on the way out. A thin
wrapper over `scan_prompt` – identical detectors (value_match + PII
regex), differing only in the audit `edge` label (`"response"`).

#### Usage

    DataShield$scan_response(
      text,
      on_fail = c("redact", "block", "ask"),
      scanners = c("regex", "value_match"),
      on_progress = NULL,
      context = list()
    )

#### Arguments

- `text`:

  Character scalar. The model's final reply.

- `on_fail`:

  `"redact"` (default), `"block"`, or `"ask"`.

- `scanners`:

  Subset of `c("regex", "value_match")`; default both.

- `on_progress`:

  Optional progress callback (see `scan_prompt`).

- `context`:

  Optional non-sensitive context; `edge` is forced to `"response"`.

#### Returns

Same shape as `scan_prompt`.

------------------------------------------------------------------------

### `DataShield$add_scanner()`

Add a custom scanner function to the end of the egress pipeline.

#### Usage

    DataShield$add_scanner(name, fn)

------------------------------------------------------------------------

### `DataShield$set_egress_ask()`

Set the sync/promise egress approval callback.

#### Usage

    DataShield$set_egress_ask(fn = NULL)

#### Arguments

- `fn`:

  Function receiving non-sensitive event metadata and returning
  `redact`, `block`, or (when enabled) `raw_once`; NULL clears it.

------------------------------------------------------------------------

### `DataShield$bind_reviewer_factory()`

Bind codeagent's parent-provider reviewer Chat factory.

#### Usage

    DataShield$bind_reviewer_factory(fn)

#### Arguments

- `fn`:

  Function accepting optional model and returning a fresh Chat.

------------------------------------------------------------------------

### `DataShield$audit()`

Return a copy of non-sensitive decision events.

#### Usage

    DataShield$audit(limit = NULL)

#### Arguments

- `limit`:

  Optional number of most recent events.

------------------------------------------------------------------------

### `DataShield$clear_audit()`

Remove all in-memory audit events.

#### Usage

    DataShield$clear_audit()

------------------------------------------------------------------------

### `DataShield$clear()`

Remove one dataset, or all datasets when name is NULL.

#### Usage

    DataShield$clear(name = NULL)

------------------------------------------------------------------------

### `DataShield$close()`

Clear sensitive state and close the shield.

#### Usage

    DataShield$close()

------------------------------------------------------------------------

### `DataShield$coverage()`

Summarise non-sensitive runtime coverage.

#### Usage

    DataShield$coverage()

## Examples

``` r
# Easy one-client declaration:
specs <- list(
  shield_describe(k_anon = 5),
  shield_egress(max_rows = 0),
  shield_regex(on_fail = "redact")
)

# Explicit lifecycle for uploaded data / selected shared chats:
shield <- DataShield$new(strategies = specs)
shield$register_data(iris, name = "iris",
  sensitivity = c(Species = "measure"))
shield$coverage()
#> $config
#> $config$max_rows
#> [1] 0
#> 
#> $config$distributions
#> [1] "off"
#> 
#> $config$k_anon
#> [1] 5
#> 
#> $config$category_max
#> [1] 20
#> 
#> $config$category_ratio
#> [1] 0.2
#> 
#> $config$detectors
#> [1] "row_cap"     "value_match"
#> 
#> $config$on_fail
#> [1] "redact"
#> 
#> $config$allow_raw_approval
#> [1] FALSE
#> 
#> $config$approval_timeout
#> [1] 60
#> 
#> $config$describe_enabled
#> [1] TRUE
#> 
#> $config$egress_enabled
#> [1] TRUE
#> 
#> 
#> $datasets
#> [1] "iris"
#> 
#> $assets
#> NULL
#> 
#> $indexed_values
#> [1] 0
#> 
#> $raw_access_columns
#> [1] 0
#> 
#> $egress_pipeline
#> [1] "egress" "regex" 
#> 
#> $ingress_pipeline
#> character(0)
#> 
#> $audit_events
#> [1] 0
#> 
#> $audit_max
#> [1] 1000
#> 
#> $egress_approval_callback
#> [1] FALSE
#> 
#> $tool_policy_default
#> [1] "scan"
#> 
#> $tool_policy_rules
#> NULL
#> 
#> $sandbox
#> NULL
#> 
#> $reviewers
#> [1] 0
#> 
#> $reviewer_factory_bound
#> [1] FALSE
#> 
#> $closed
#> [1] FALSE
#> 
```
