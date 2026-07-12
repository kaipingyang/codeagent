# Switch the active model on a CodeagentClient, preserving history

Tries Route A (in-place provider swap); falls back to Route B (rebuild +
migrate turns) if the in-place swap fails. The returned client always
has the full conversation history and re-registered tools.

## Usage

``` r
switch_model(client, model)
```

## Arguments

- client:

  A `CodeagentClient` from
  [`codeagent_client()`](https://github.com/kaipingyang/codeagent/reference/codeagent_client.md).

- model:

  Character. New model spec/alias (see
  [`.resolve_model_chat()`](https://github.com/kaipingyang/codeagent/reference/dot-resolve_model_chat.md)).

## Value

A `CodeagentClient` with the new model and preserved history. With Route
A this is the SAME client object (Chat identity unchanged); with Route B
it is a NEW client object.
