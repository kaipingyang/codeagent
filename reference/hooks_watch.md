# Filesystem-watch hooks (FileChanged / ConfigChange)

Bridges the `watcher` package (libfswatch / inotify) to the
`FileChanged` and `ConfigChange` hook events. The watcher runs in the
background and dispatches callbacks through the `later` event loop, so
it works wherever a `later` loop is being pumped: the Shiny app (its
reactive loop) and the CLI REPL (which pumps `later` while streaming
and, since the non-blocking keypress change, while idle at the prompt
too).

`watcher`'s callback only reports the CHANGED PATHS, not whether each
was a create/modify/delete – so `FileChanged`'s `event` field is always
`"change"` here (documented downgrade; CC distinguishes
change/add/unlink).
