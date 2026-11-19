# shinychat history over codeagent's session log

A
[`shinychat::history_options()`](https://posit-dev.github.io/shinychat/r/reference/history_options.html)
for personal use: the history column lists every codeagent session of
the project – earlier ones included – straight from codeagent's session
log, without a second copy of any conversation. Renames and titles are
kept in the log; opening a conversation lets the model continue from its
saved context. Conversations are partitioned by user.

## Usage

``` r
codeagent_history_options(cwd = getwd(), user = NULL, max_store_mb = NULL, ...)
```

## Arguments

- cwd:

  Project directory; selects the session directory.

- user:

  Partition key. A string, or `function(session)` returning one. The
  default uses the authenticated `session$user`, else the account name
  running the app. Sessions saved before owners were recorded belong to
  the account running the app.

- max_store_mb:

  Size limit per user and project. `NULL` (default): no limit. A number
  lets shinychat delete the oldest session logs of that user and project
  once the limit is exceeded.

- ...:

  Further arguments to
  [`shinychat::history_options()`](https://posit-dev.github.io/shinychat/r/reference/history_options.html)
  (e.g. `restore_mode`, `title`).

## Value

A shinychat history configuration.

## Details

`codeagent_app(ui_layout = "dsh")` uses it. A deployed host app keeps
shinychat's own history instead:
`codeagent_server(history = shinychat::history_options(...))` with the
store of its choice.
