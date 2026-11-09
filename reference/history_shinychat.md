# shinychat conversation history for host apps

`codeagent_server(history = shinychat::history_options(...))`:
shinychat's history drawer (list, switch, new, rename, delete) on top of
codeagent's engine.

shinychat records a conversation from the turns of the Chat it is given,
after each `chat_append()` stream. codeagent therefore gives it a
separate *presentation* Chat that holds what the user saw – user
messages without the injected `<system-reminder>`, tool calls with gated
arguments, model text after the Data Shield output gate – and only ever
grows: compaction changes the model's context, never this record. The
model's own context is restored from codeagent's session log
([`save_session()`](https://kaipingyang.github.io/codeagent/reference/save_session.md))
through the session id stored with each record.
