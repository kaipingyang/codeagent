# How codeagent works: concepts and boundaries

**Language:** English \|
[简体中文](https://kaipingyang.github.io/codeagent/articles/architecture-concepts-cn.md)

This article is the conceptual map of codeagent. It explains the order
of a turn, the separation between authorization and extensibility, and
the context lifecycle around every provider request. For file- and
symbol-level structure, see [Code architecture
map](https://kaipingyang.github.io/codeagent/articles/architecture-code-map.md).

The diagrams deliberately omit volatile counts, model names, and token
thresholds. Detailed defaults remain in the linked topic articles and
API reference.

## Reading the visual language

| Visual              | Meaning                                            |
|---------------------|----------------------------------------------------|
| Blue                | user, host, entry, or portable result              |
| Purple              | model/provider work or model-generated summaries   |
| Amber/red           | policy, authorization, rejection, or recovery      |
| Green               | execution or a safe/validated result               |
| Teal/gray           | lifecycle, context, internal state, or persistence |
| Solid arrow         | main call/data path                                |
| Dashed/dotted arrow | callback, state, or persistence relationship       |

## One foreground turn

[View full-size diagram
↗](https://kaipingyang.github.io/codeagent/articles/diagrams/svg/agent-turn-lifecycle.drawio.svg)

[![One codeagent turn from user input through input safety, turn setup,
provider and tool rounds, response finalization, output safety, and
session
persistence](diagrams/svg/agent-turn-lifecycle.drawio.svg)](https://kaipingyang.github.io/codeagent/articles/diagrams/svg/agent-turn-lifecycle.drawio.svg)

**Audience:** User / Integrator **Sources:** `R/stream.R`,
`R/turn_pipeline.R`, `R/input_gate.R`, `R/output_gate.R`, `R/sessions.R`

A turn has five stable stages:

1.  **Input boundary.** Text and text-bearing attachments pass through
    the input gate before reaching the model. A Data Shield may redact,
    ask, or block.
2.  **Turn setup.** The harness adds dynamic context and reminders,
    manages resources, and prepares request-boundary compaction.
3.  **Provider/tool rounds.** ellmer drives one or more provider
    requests. A tool request enters the safety pipeline below, executes
    only after authorization, and returns a normalized result to the
    next provider request.
4.  **Final response boundary.** Finish reason and deterministic
    citations are finalized before the output gate. Shield/citation
    modes buffer the response; raw provider deltas never reach the
    browser first.
5.  **Teardown and persistence.** Usage and lifecycle hooks run, then
    the session stores lossless provider-facing state plus a
    presentation view.

The diagram shows
[`codeagent_stream_async()`](https://kaipingyang.github.io/codeagent/reference/codeagent_stream_async.md),
but the same boundaries are reused by one-shot, REPL, and Shiny
adapters. The adapters own presentation; the Chat and turn services own
model/tool state.

### Important turn invariants

- A tool preview is not approval.
- A failed or rejected tool does not bypass the central gate through
  another UI entrypoint.
- Shield and citation buffering occurs on the server, not by hiding data
  that was already sent to the browser.
- Session presentation may be redacted while lossless provider-facing
  state is retained separately; storage policy is an independent
  security concern.

Related articles:

- [Permissions](https://kaipingyang.github.io/codeagent/articles/permissions.md)
- [Data
  Shield](https://kaipingyang.github.io/codeagent/articles/data-shield.md)
- [Backend
  integration](https://kaipingyang.github.io/codeagent/articles/backend-integration.md)
- [Tool
  artifacts](https://kaipingyang.github.io/codeagent/articles/tool-artifacts.md)

## Tool-call safety pipeline

[View full-size diagram
↗](https://kaipingyang.github.io/codeagent/articles/diagrams/svg/tool-safety-pipeline.drawio.svg)

[![Tool request safety pipeline showing pre-gate preview, central
permission authority, Data Shield ingress, approval, PreToolUse rewrite
and recheck, execution, result filtering, PostToolUse, and
normalization](diagrams/svg/tool-safety-pipeline.drawio.svg)](https://kaipingyang.github.io/codeagent/articles/diagrams/svg/tool-safety-pipeline.drawio.svg)

**Audience:** Integrator / Maintainer **Sources:** `R/tools_gate.R`,
`R/tool_input_hook.R`, `R/hooks.R`, `R/data_shield.R`, `R/stream.R`

Three responsibilities are adjacent but intentionally separate:

1.  **Permission is the authority.** The central gate interprets tool
    metadata, enabled sets, capability policy, per-tool overrides,
    modes, and rules. An `ask` decision is resolved by the host’s
    `ask_fn`; no callback means deny.
2.  **Hooks are extension points.** `PreToolUse` may deny or rewrite
    arguments. Rewritten arguments are sent through permission and
    Shield checks again. `PostToolUse` runs after the result path.
3.  **Data Shield protects model boundaries.** Ingress scans arguments
    before execution; egress filters the result before it returns to the
    model. Shield bypass never bypasses the independent permission gate.

`codeagent_stream_async(on_tool_request=)` emits a **pre-gate preview**
for UI feedback. It must not create an approval decision or mark
execution as started. Actual approval is driven by
`install_permission_gate(..., ask_fn=)` and correlated with the same
tool-call id.

The result is normalized into three channels:

``` text
value      portable model/UI text fallback
artifact   versioned UI-neutral structured data
display    optional shinychat adapter
```

Non-shinychat hosts consume `artifact` and fall back to `value`; they do
not parse `display` HTML.

## Request-boundary context management

[View full-size diagram
↗](https://kaipingyang.github.io/codeagent/articles/diagrams/svg/context-compaction-lifecycle.drawio.svg)

[![Context management before each provider request: pending turn
snapshot, resource replacement, token accounting, micro-snip, history
rebuild, fresh recount, optional summaries, validation, provider
request, and prompt-too-long
recovery](diagrams/svg/context-compaction-lifecycle.drawio.svg)](https://kaipingyang.github.io/codeagent/articles/diagrams/svg/context-compaction-lifecycle.drawio.svg)

**Audience:** Integrator / Maintainer **Sources:** `R/compaction.R`,
`R/resource.R`, `R/turn_pipeline.R`

Current compaction is attached to ellmer’s `on_request_start`, so it
runs before **every provider request**, including internal tool-loop
rounds. The callback’s outgoing turns already contain the pending turn.

The ordering is intentional:

1.  Replace eligible large historical tool results.
2.  Perform initial model-aware accounting.
3.  Apply a cheap, budget-aware micro-snip before asking another model
    to summarize.
4.  Rebuild persisted history plus the original pending turn **exactly
    once**.
5.  Recount the rebuilt structure; stale provider usage is not a
    post-mutation lower bound.
6.  Only if still over budget, attempt incremental summary and then the
    optional full-summary fallback.
7.  Validate tool request/result pairing before sending the provider
    request.

If the provider still reports prompt-too-long/413, recovery drops
complete historical API rounds, validates the result, and retries once.
It never removes an arbitrary half of a tool request/result pair.

See [Context
compaction](https://kaipingyang.github.io/codeagent/articles/compaction.md)
for thresholds, controls, and failure semantics.

## State and ownership boundaries

| State | Owner | Sharing rule |
|----|----|----|
| Provider/model configuration | ellmer Chat | cloned or reconstructed only through verified paths |
| Tool set + permission callback | Chat / host | subagents may only narrow the parent’s actual tools |
| Turn lifecycle | harness | shared by one-shot, stream, REPL, and Shiny adapters |
| Data Shield engine | client/session | foreground codeagent-owned clones may share the same live engine |
| Browser UI state | host adapter | never an authorization source |
| Session JSONL | codeagent session store | contains lossless state and presentation records |
| Process worker state | worker process | receives an immutable security snapshot, not parent mutable state |

These boundaries explain why codeagent does not register
[`shinychat::chat_server()`](https://posit-dev.github.io/shinychat/r/reference/chat_app.html):
codeagent must remain the single owner of streaming, permissions, hooks,
Data Shield, and persistence even when shinychat owns the visual
components.

## Where details live

| Question | Article |
|----|----|
| How does the permission gate decide? | [Permissions](https://kaipingyang.github.io/codeagent/articles/permissions.md) |
| How are three model boundaries protected? | [Data Shield](https://kaipingyang.github.io/codeagent/articles/data-shield.md) |
| How is context compacted? | [Compaction](https://kaipingyang.github.io/codeagent/articles/compaction.md) |
| How do subagents and teams differ? | [Team coordination](https://kaipingyang.github.io/codeagent/articles/team-coordination.md) |
| How can another UI host codeagent? | [Backend integration](https://kaipingyang.github.io/codeagent/articles/backend-integration.md) |
| How should a UI consume tool results? | [Tool artifacts](https://kaipingyang.github.io/codeagent/articles/tool-artifacts.md) |
| How are skills discovered and loaded? | [Skills](https://kaipingyang.github.io/codeagent/articles/skills-usage.md) |

## Diagram maintenance

Editable draw.io sources live under `vignettes/diagrams/src/`; generated
SVGs live under `vignettes/diagrams/svg/`. Each diagram records its
primary source files and verified commit. See
`vignettes/diagrams/README.md` for rendering and validation commands.
