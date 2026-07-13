# Export the current WEAR exploration session to a Quarto document

Generates a reproducible `.qmd` file from the conversation history of a
`wear_explore()` session. Each user message becomes a `##` section
heading; assistant text is written as prose; code from `ExploreData`
tool results is written as fenced R code chunks.

## Usage

``` r
generate_wear_report(
  client,
  path = paste0("exploration-", format(Sys.Date(), "%Y%m%d"), ".qmd"),
  title = "Data Exploration Report"
)
```

## Arguments

  - client:
    
    A `CodeagentClient` whose `chat` has been used in a `wear_explore()`
    session.

  - path:
    
    Character. Output file path (default: `exploration-YYYYMMDD.qmd` in
    the current directory).

  - title:
    
    Character. Quarto document title.

## Value

Invisibly the path to the generated `.qmd` file.

## Details

The `.qmd` has `eval: false` by default so it renders without re-running
the LLM queries. Set `eval: true` in the YAML front-matter to make it
fully reproducible.

This function is also registered as the `GenerateReport` tool inside a
`wear_explore()` session, so the agent can call it when the user types
`/report`.

## See also

`wear_explore()` to start a WEAR exploration session.

## Examples

``` r
if (FALSE) { # \dontrun{
# After a wear_explore() session:
client <- wear_explore(data = list(mtcars = mtcars))

# Export to a named file
path <- generate_wear_report(client,
  path  = "mtcars-analysis.qmd",
  title = "Motor Trend Analysis")

# Render with quarto CLI
system(paste("quarto render", path))
# Or: quarto::quarto_render(path)  # if quarto R package is installed
} # }
```
