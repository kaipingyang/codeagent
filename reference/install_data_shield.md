# Install the Data Shield egress guard on a Chat (P0)

Wrap every tool currently registered on `chat` so bulk rows and
registered protected values are filtered before reaching the model. The
mutable `DataShieldState` is per user session and may be shared by
multiple chat threads in that session. Calling again wraps newly
registered tools and is otherwise idempotent.

Pass a `CodeagentClient` directly, or a Chat plus `shield=`. For a
harness-only client, register host tools first, then call this function.

## Usage

``` r
install_data_shield(chat, max_rows = NULL, shield = NULL)
```

## Arguments

- chat:

  An [`ellmer::Chat`](https://ellmer.tidyverse.org/reference/Chat.html)
  or `CodeagentClient`.

- max_rows:

  Optional integer override for rows retained from bulk output.

- shield:

  Optional
  [`data_shield()`](https://kaipingyang.github.io/codeagent/reference/data_shield.md)
  state. Required only when `chat` is a bare Chat that does not already
  have a shield attached.

## Value

Invisibly, the Chat.

## See also

[`data_shield()`](https://kaipingyang.github.io/codeagent/reference/data_shield.md),
[`register_protected_data()`](https://kaipingyang.github.io/codeagent/reference/register_protected_data.md),
[`codeagent_client()`](https://kaipingyang.github.io/codeagent/reference/codeagent_client.md)
