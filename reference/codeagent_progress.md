# Report a running tool's progress in the chat

Call it at the start of a host tool (synchronously, before the tool
returns its promise) and keep the handle:
[`update()`](https://rdrr.io/r/stats/update.html) changes the step
shown, `done()` removes the line. The line is shown above the chat input
of the session that runs the tool, with the seconds elapsed counted in
the browser.

## Usage

``` r
codeagent_progress(
  label,
  step = "",
  typical = NULL,
  delay = 3,
  session = shiny::getDefaultReactiveDomain()
)
```

## Arguments

- label:

  Character(1). What is running, e.g. `"t_ae_socpt_grd"`.

- step:

  Character(1). The first step shown (optional).

- typical:

  Numeric(1) or `NULL`. Seconds it usually takes; shown as "usually ~N
  s" when given.

- delay:

  Seconds before the line appears (default 3).

- session:

  The Shiny session; defaults to the current one.

## Value

A `codeagent_progress` handle: a list with
`update(step, typical = NULL)` and `done()`. Without a session both do
nothing.

## See also

[`codeagent_server()`](https://kaipingyang.github.io/codeagent/reference/codeagent_server.md)
