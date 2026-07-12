# Start a WEAR loop data exploration session

Launches an **interactive** data exploration session using the
Write/Execute/Analyze/Regroup (WEAR) loop pattern. This is a **dedicated
exploration mode** – it is separate from a normal
[`codeagent_app()`](https://github.com/kaipingyang/codeagent/reference/codeagent_app.md)
or
[`codeagent_console()`](https://github.com/kaipingyang/codeagent/reference/codeagent_console.md)
session. The difference:

## Usage

``` r
wear_explore(data = NULL, client = NULL, mode = c("repl", "shiny"), ...)
```

## Arguments

- data:

  Named list, environment, or `NULL`. Data.frames to make available for
  exploration. If `NULL`, uses objects in `.GlobalEnv`. A named list is
  converted to an environment automatically.

- client:

  A `CodeagentClient` (from
  [`codeagent_client()`](https://github.com/kaipingyang/codeagent/reference/codeagent_client.md)).
  If `NULL`, one is built from `~/.codeagent/settings.json` with
  `permission_mode = "bypass"`.

- mode:

  Character. `"repl"` (default) starts an interactive CLI session;
  `"shiny"` launches the Shiny app.

- ...:

  Passed to
  [`codeagent_console()`](https://github.com/kaipingyang/codeagent/reference/codeagent_console.md)
  or
  [`codeagent_app()`](https://github.com/kaipingyang/codeagent/reference/codeagent_app.md).

## Value

Invisibly the `CodeagentClient` (useful for post-session inspection or
calling
[`generate_wear_report()`](https://github.com/kaipingyang/codeagent/reference/generate_wear_report.md)
manually).

## Details

|  |  |
|----|----|
| Normal session | WEAR session (`wear_explore()`) |
| No data registered by default | `data=` argument registers named data.frames |
| No `GenerateReport` tool | `/report` exports session to `.qmd` |
| No WEAR system prompt | Agent instructed to end each turn with **Next steps** |
| General-purpose tools | `ExploreData` tool added (read-only, sandboxed) |

The `ExploreData` and `GenerateReport` tools are **not** registered in
the standard agent loop
([`codeagent_app()`](https://github.com/kaipingyang/codeagent/reference/codeagent_app.md))
– use `wear_explore()` to enter exploration mode explicitly.

## See also

[`generate_wear_report()`](https://github.com/kaipingyang/codeagent/reference/generate_wear_report.md)
to export the session to a Quarto document.

## Examples

``` r
if (FALSE) { # \dontrun{
# Explore mtcars from the CLI (requires a configured LLM client)
wear_explore(data = list(mtcars = mtcars))

# Shiny UI with multiple data.frames
wear_explore(
  data = list(sales = sales_df, products = products_df),
  mode = "shiny"
)

# Capture the client to export the report afterwards
client <- wear_explore(data = list(mtcars = mtcars))
generate_wear_report(client, title = "Motor Trend Analysis")
} # }
```
