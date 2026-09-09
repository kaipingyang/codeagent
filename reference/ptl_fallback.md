# Pair-safe prompt-too-long fallback

Drops complete historical API rounds until the estimated request
releases the provider-reported token gap. Without an actual/limit pair,
targets a 20% reduction. The newest round and pending turn are always
retained.

## Usage

``` r
ptl_fallback(chat, drop_turns = 3L, error_msg = NULL, pending_turn = NULL)
```

## Arguments

- chat:

  An [`ellmer::Chat`](https://ellmer.tidyverse.org/reference/Chat.html)
  object.

- drop_turns:

  Deprecated compatibility argument; raw turns are never dropped
  independently.

- error_msg:

  Character or NULL. Provider PTL message.

- pending_turn:

  Optional pending turn, retained outside persisted history.

## Value

A sanitized internal recovery decision.
