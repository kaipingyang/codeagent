# Data Shield — pluggable strict data-safety valve (P0 core)

Opt-in guard that stops raw row-level data from reaching the LLM via the
two inbound edges: (1) prompt-side auto-injection (ambient context) and
(2) tool results. Off by default (`data_shield = NULL`).

This file contains the P0 core: a content-agnostic, shape-based **egress
row-cap** for tool results (edge 2). It does NOT inspect code or block
`print`; it looks only at the *shape* of a tool's returned text and
truncates output that has the signature of a bulk row-level data dump,
passing scalars, messages, model summaries, plots and errors through
untouched.
