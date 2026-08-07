# Start filesystem-watch hooks for a session.

Start filesystem-watch hooks for a session.

## Usage

``` r
.start_hook_watchers(hooks, cwd = getwd(), config_paths = NULL, latency = 1)
```

## Arguments

- hooks:

  A
  [HookRegistry](https://kaipingyang.github.io/codeagent/reference/HookRegistry.md)
  or NULL. NULL / no watcher package -\> no-op.

- cwd:

  Directory to watch recursively for `FileChanged`.

- config_paths:

  Character vector of settings-file paths to watch for `ConfigChange`
  (defaults to user + project settings.json).

- latency:

  Numeric seconds; watcher debounce (default 1).

## Value

A list with a `$stop()` method (idempotent) and the watcher objects, or
NULL if nothing could be started. Store it and call `$stop()` on session
teardown.
