# Run a sub-agent's conversation loop, optionally persisting its session

When `persist = TRUE` the sub-agent's full conversation is saved to a
"sidechain" JSONL under the project's session directory (id prefixed
with `subagent-`), so sub-agent history survives instead of being
ephemeral.

## Usage

``` r
.run_subagent_loop(
  sub_chat,
  prompt,
  max_turns = 30L,
  persist = FALSE,
  cwd = getwd(),
  description = NULL,
  data_shield = NULL
)
```

## Arguments

- sub_chat:

  An [`ellmer::Chat`](https://ellmer.tidyverse.org/reference/Chat.html)
  for the sub-agent.

- prompt:

  Character. The task prompt.

- max_turns:

  Integer. Max turns (currently single-shot chat).

- persist:

  Logical. Save the sub-agent session to disk.

- cwd:

  Character. Project dir for session storage.

- description:

  Character. Used as the sidechain session title.

- data_shield:

  Optional
  [DataShield](https://kaipingyang.github.io/codeagent/reference/DataShield.md).
  Replies are gated before hooks, return, or persistence. Shielded
  sidechains are not persisted.

## Value

Character. The sub-agent's text response.
