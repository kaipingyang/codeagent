# inst/evals/tasks/data_explore.R
# Eval task: ExploreData tool -- schema, query, isolation.

library(vitals)
library(tibble)
library(codeagent)
library(ellmer)

# ---------------------------------------------------------------------------
# Dataset
# ---------------------------------------------------------------------------

data_explore_dataset <- tribble(
  ~input, ~target,

  # Schema request: agent should return column names
  paste0("Use the ExploreData tool on 'mtcars' (no code) to get its schema. ",
         "How many columns does it have? Reply with only a number."),
  "11",

  # Simple query: row count
  paste0("Use ExploreData on 'mtcars' with code `nrow(mtcars)` to count rows. ",
         "Reply with only the number."),
  "32",

  # Aggregation query
  paste0("Use ExploreData on 'mtcars' with code ",
         "`mean(mtcars$mpg)` to get mean mpg. ",
         "Reply with only the number (to 1 decimal)."),
  "20\\.1",

  # Isolation: source data unchanged after mutating attempt
  paste0("Use ExploreData on 'mtcars' with code ",
         "`mtcars$NEW_COL <- 999; 'done'`. ",
         "Then check: use ExploreData on 'mtcars' (no code) and tell me ",
         "whether NEW_COL appears in the schema. Reply YES or NO."),
  "NO"
)

# ---------------------------------------------------------------------------
# Solver: registers ExploreData and evaluates
# ---------------------------------------------------------------------------

data_explore_solver <- function() {
  function(input) {
    ch <- codeagent_client(
      permission_mode = "bypass",
      btw_groups = NULL,
      cwd = getwd()
    )
    # Inject mtcars into the execution environment
    register_explore_data_tool(ch$chat, envir = list2env(list(mtcars = mtcars),
                                                          parent = baseenv()))
    tryCatch(
      codeagent(ch, input),
      error = function(e) paste0("[Error] ", conditionMessage(e))
    )
  }
}

# ---------------------------------------------------------------------------
# Task
# ---------------------------------------------------------------------------

data_explore_task <- Task$new(
  dataset = data_explore_dataset,
  solver  = generate(data_explore_solver()),
  scorer  = detect_includes(case_sensitive = FALSE)
)
