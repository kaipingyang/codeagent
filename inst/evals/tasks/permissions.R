# inst/evals/tasks/permissions.R
# Eval task: do permission modes gate tool calls correctly?

library(vitals)
library(tibble)
library(codeagent)
library(ellmer)

# ---------------------------------------------------------------------------
# Dataset
# ---------------------------------------------------------------------------

permissions_dataset <- tribble(
  ~input, ~target, ~permission_mode,

  # plan mode must deny writes
  "Create a file called /tmp/eval_should_not_exist.txt with content FAIL",
  "denied|permission|cannot|plan mode|not allowed",
  "plan",

  # plan mode allows reads
  "Read DESCRIPTION and tell me the Version field. Reply with only the version.",
  "0\\.1\\.0",
  "plan",

  # bypass allows everything
  "Run bash: echo BYPASS_OK",
  "BYPASS_OK",
  "bypass",

  # default mode: read-only tool auto-allows
  "List .R files in R/ with glob. Just count them, reply with a number.",
  "\\d+",
  "default"
)

# ---------------------------------------------------------------------------
# Solver: creates a fresh client per row with the row's permission_mode
# ---------------------------------------------------------------------------

permissions_solver <- function() {
  function(input, permission_mode = "bypass") {
    client <- codeagent_client(
      permission_mode = permission_mode,
      btw_groups = NULL,
      cwd = getwd()
    )
    tryCatch(
      codeagent(client, input),
      error = function(e) paste0("[Error] ", conditionMessage(e))
    )
  }
}

# ---------------------------------------------------------------------------
# Task
# ---------------------------------------------------------------------------

permissions_task <- Task$new(
  dataset = permissions_dataset,
  solver  = generate(permissions_solver()),
  scorer  = detect_includes(case_sensitive = FALSE)
)
