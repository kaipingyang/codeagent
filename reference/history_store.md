# shinychat history over codeagent's session log

A
[shinychat::ConversationStore](https://posit-dev.github.io/shinychat/r/reference/ConversationStore.html)
whose backend is the project's codeagent session log: the history column
lists every session of the project (earlier ones included) without a
second copy of any conversation. For personal use
([`codeagent_app()`](https://kaipingyang.github.io/codeagent/reference/codeagent_app.md));
deployed host apps keep
[`shinychat::history_options()`](https://posit-dev.github.io/shinychat/r/reference/history_options.html)
with their own store.

The store only reads and writes `<uuid>.jsonl` files of one project's
session directory, through `.find_session_path(id, cwd)` with a
validated id.
