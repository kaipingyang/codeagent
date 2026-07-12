# Data exploration with codeagent

## Two modes: standard vs WEAR

codeagent offers two ways to explore data. Choosing the right one
depends on whether you want a focused, stateful exploration session or
just an occasional data query inside a general-purpose agent
conversation.

|  | Standard session | WEAR session ([`wear_explore()`](https://github.com/kaipingyang/codeagent/reference/wear_explore.md)) |
|----|----|----|
| Entry point | [`codeagent_app()`](https://github.com/kaipingyang/codeagent/reference/codeagent_app.md) / [`codeagent_console()`](https://github.com/kaipingyang/codeagent/reference/codeagent_console.md) | `wear_explore(data = ...)` |
| `ExploreData` tool | Not registered by default | Automatically registered |
| `/report` command | Not available | Exports session to `.qmd` |
| WEAR system prompt | Not injected | Injected: agent ends each turn with **Next steps** |
| Typical use | Occasional data questions amid coding tasks | Dedicated analysis / EDA session |

**Rule of thumb:** use
[`wear_explore()`](https://github.com/kaipingyang/codeagent/reference/wear_explore.md)
when data exploration *is* the task. Use a standard session when data
questions are one of many things you need.

------------------------------------------------------------------------

## Standard session: ExploreData on demand

You can register `ExploreData` manually on any client:

``` r

library(codeagent)

client <- codeagent_client(permission_mode = "bypass", btw_groups = NULL)
register_explore_data_tool(client$chat)

codeagent(client, "How many rows are in mtcars and what are the columns?")
codeagent(client, "What is the average mpg per cylinder count?")
```

`ExploreData` is read-only (sandboxed sub-environment of `.GlobalEnv`)
and is allowed automatically in `default` permission mode.

------------------------------------------------------------------------

## WEAR session: dedicated exploration

[`wear_explore()`](https://github.com/kaipingyang/codeagent/reference/wear_explore.md)
starts a full exploration session with the Write/Execute/Analyze/Regroup
loop. On every turn the agent:

1.  **W** — writes dplyr/base R code to answer your question
2.  **E** — runs it via `ExploreData`
3.  **A** — interprets results, flags patterns and outliers
4.  **R** — proposes 3-5 follow-up questions

&nbsp;

    wear_explore(data = ...)
      - resolve data into an environment
      - register ExploreData tool (read-only, sandboxed child env)
      - register /report (GenerateReport) tool
      - inject the WEAR system prompt
      - enter codeagent_console()  or  codeagent_app()

    Each turn the agent runs the W-E-A-R cycle:
      W  Write     model writes dplyr / base R code
      E  Execute   ExploreData: eval in new.env(parent = data env)
                   (read-only: your source data is never mutated)
                     - code given -> returns table / printed value
                     - no code    -> returns ellmer::df_schema(df) to plan next step
      A  Analyze   model interprets the result, flags patterns / outliers
      R  Regroup   model ends the turn with a "Next steps" list (3-5 items)
           |
           v  (repeat until you stop)
      /report -> generate_wear_report(): turns -> Quarto .qmd
                 user Q = "##" heading, tool code -> an {r} chunk, analysis = prose

``` r

# CLI session (blocks until you type /exit or Ctrl+C)
wear_explore(data = list(mtcars = mtcars))

# Shiny UI
wear_explore(
  data = list(sales = sales_df, products = products_df),
  mode = "shiny"
)
```

### Exporting to Quarto

Type `/report` in the chat (or say “export my analysis”) to save the
session as a reproducible `.qmd` file. The `/report` command is **only
available inside a
[`wear_explore()`](https://github.com/kaipingyang/codeagent/reference/wear_explore.md)
session** — it is not registered in standard sessions.

``` r

# Capture the client to generate the report after the session ends
client <- wear_explore(data = list(mtcars = mtcars))

path <- generate_wear_report(
  client,
  path  = "mtcars-analysis.qmd",
  title = "Motor Trend Car Analysis"
)

# Render with the quarto CLI
system(paste("quarto render", path))
```

The generated `.qmd` contains:

- Each user question as a `##` section heading
- Agent code as ```` ```{r} ```` chunks (`eval: false` by default)
- Agent analysis as prose
- YAML front-matter with `code-fold: true` and `toc: true`

------------------------------------------------------------------------

## Environment context injection

Enable automatic schema injection so the agent always knows what
data.frames are in `.GlobalEnv` without an explicit tool call:

``` json
// ~/.codeagent/settings.json
{
  "inject_r_env": true
}
```

------------------------------------------------------------------------

## Security

`ExploreData` runs code in a **sub-environment** that shares bindings
with `.GlobalEnv` but cannot assign back to it (copy-on-modify
semantics). Mutations (`df$x <- ...`) affect only the sandboxed copy,
never your original data.

The tool is marked `read_only_hint = TRUE` and does not have access to
the file system or network. For full capabilities, use the standard
`RunR` tool (subject to its own permission gate).
