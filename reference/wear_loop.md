# WEAR Loop Data Exploration

Implements Databot's WEAR loop (Write/Execute/Analyze/Regroup) for
interactive data exploration. Each cycle: the agent writes dplyr/R code,
executes it via `ExploreData`, analyzes the result, then proposes 3-5
next steps for the user to choose from.

Use `/report` in the chat to export the session to a Quarto document.
