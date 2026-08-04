# Install the Data Shield egress guard on a Chat (P0)

Opt-in strict data-safety guard. Wraps every tool currently registered
on `chat` so that bulk row-level data in a tool's result is truncated to
a shape summary before it reaches the model (edge 2 of the two inbound
edges; see the `data-shield` vignette). Off by default; call once
**after** all tools are registered. Content-agnostic and shape-based –
it does not inspect code or block `print`.

## Usage

``` r
install_data_shield(chat, max_rows = 0L)
```

## Arguments

- chat:

  An [`ellmer::Chat`](https://ellmer.tidyverse.org/reference/Chat.html).

- max_rows:

  Integer. Rows to keep before truncating a bulk tabular result (`0` =
  shape summary only).

## Value

Invisibly, `chat`.

## See also

[`codeagent_client()`](https://kaipingyang.github.io/codeagent/reference/codeagent_client.md)
