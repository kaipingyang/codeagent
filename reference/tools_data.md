# Data Exploration Tool

An ellmer tool that lets the agent answer natural-language questions
about data.frames in the user's R session. The agent generates
dplyr/base R code, evaluates it in a child environment, and returns the
result as a formatted table.

`ExploreData` executes arbitrary model-provided R code. The child
binding usually protects the selected data.frame through copy-on-modify,
but it is not a security sandbox or a read-only boundary: code may
access parent environments, files, processes, or networks available to
the R process.
