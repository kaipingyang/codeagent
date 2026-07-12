# Data Exploration Tool

An ellmer tool that lets the agent answer natural-language questions
about data.frames in the user's R session. The agent generates
dplyr/base R code to answer the question, executes it in a sandboxed
sub-environment, and returns the result as a formatted table.

Unlike the general RunR tool (which runs arbitrary code), `explore_data`
is scoped to read-only queries on a named data.frame. It never modifies
the source data.
