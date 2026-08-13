# Output Gate — the edge-3 counterpart of the input gate

Data Shield guards three edges into/out of the model:

- **edge 1** input gate (`R/input_gate.R`): user input BEFORE the model.

- **edge 2** tool gate (`R/tools_gate.R`): tool traffic in/out of the
  model.

- **edge 3** output gate (this file): the model's final reply BEFORE it
  reaches the user.

The output gate closes the last confidentiality gap: the model may
reproduce a protected value it inferred from tool output (an edge-2
aggregate the shield let through) even when the user's own input was
clean. Symmetric to the input gate, it reuses the shield's
`scan_response()` (a thin wrapper over `scan_prompt()` — identical
value_match + PII detectors, audited under `edge = "response"`).

**Streaming behaviour (kiro round-2/4):** when a shield is active, the
Shiny and CLI streaming paths **buffer** the reply, run the output gate
on the finished text, and emit the (possibly redacted) reply once –
nothing reaches the browser until the gate has run (no
plaintext-then-warning). The ERROR path is gated too: a partial reply is
scanned before it leaves via the return value, and the raw error string
is not surfaced. Without a shield, streaming renders token-by-token as
before (zero cost). The CLI non-streaming path holds the full `response`
and redacts it before returning.
