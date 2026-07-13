# Live team-board dashboard

A standalone Shiny app that live-monitors a shared task board
([`board_create()`](https://kaipingyang.github.io/codeagent/reference/board_create.md)
/
[`team_coordinate()`](https://kaipingyang.github.io/codeagent/reference/team_coordinate.md)):
task table (coloured by status), a progress bar, and the inter-agent
message log. Point it at the `db_path` of a team running in another
process (or a background
[`team_coordinate()`](https://kaipingyang.github.io/codeagent/reference/team_coordinate.md)).

Updates are event-driven via
[`board_watch()`](https://kaipingyang.github.io/codeagent/reference/board_watch.md)
(the `watcher` package) so the view refreshes the instant the board
changes; it falls back to periodic polling when watcher is unavailable.

## Usage

``` r
team_dashboard(db_path, poll_ms = 1500L, title = "codeagent — team board", ...)
```

## Arguments

- db_path:

  Character. Path to the board SQLite file to monitor.

- poll_ms:

  Integer. Poll interval (ms) used only when the `watcher` package is
  unavailable (event-driven otherwise). Default 1500.

- title:

  Character. Dashboard title.

- ...:

  Passed to
  [`shiny::shinyApp()`](https://rdrr.io/pkg/shiny/man/shinyApp.html)
  `options` (e.g. `port`).

## Value

A `shiny.appobj`.
