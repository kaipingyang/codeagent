# Rewind a chat to an earlier point in the conversation

Truncates the chat's in-memory turns to keep only the first `keep_turns`
user/assistant turns (ellmer counts each user and assistant message as a
separate turn, so a "round" is 2 turns). This is a pure in-memory
operation via `Chat$set_turns()`; persist afterwards with
[`save_session()`](https://kaipingyang.github.io/codeagent/reference/save_session.md)
to make the rewind durable.

## Usage

``` r
truncate_chat_turns(chat, keep_turns)
```

## Arguments

- chat:

  An [`ellmer::Chat`](https://ellmer.tidyverse.org/reference/Chat.html)
  object (modified in place).

- keep_turns:

  Integer. Number of turns to keep from the start. If `NULL` or larger
  than the current turn count, nothing is truncated.

## Value

Invisibly the number of turns kept.
