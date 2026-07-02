# inst/evals/tasks/tool_use.R
# Eval task: does the agent correctly use core tools?
# Tests Read, Bash, Glob -- the most fundamental harness capabilities.

library(vitals)
library(tibble)

# ---------------------------------------------------------------------------
# Dataset
# ---------------------------------------------------------------------------

tool_use_dataset <- tribble(
  ~input, ~target,

  # Read tool
  paste0("Read the file DESCRIPTION and tell me the Package name. ",
         "Reply with ONLY the package name, nothing else."),
  "codeagent",

  # Glob tool
  paste0("How many .R files are in the R/ directory? ",
         "Reply with ONLY a number."),
  "\\d+",    # any number -- scored with detect_match(regex=TRUE)

  # Bash tool
  paste0("Run the bash command `echo EVAL_OK` and tell me what it printed. ",
         "Reply with ONLY the output."),
  "EVAL_OK",

  # Combining tools: read + count
  paste0("Use tools to count the number of exported functions in NAMESPACE ",
         "(lines starting with 'export('). Reply with ONLY a number."),
  "\\d+"
)

# ---------------------------------------------------------------------------
# Solver: codeagent_client drives the agent
# ---------------------------------------------------------------------------

codeagent_solver <- function() {
  function(input) {
    client <- getOption("codeagent.eval_chat")
    if (is.null(client))
      stop("Run setup_eval_client.R first to configure codeagent.eval_chat")
    # Fresh turns per eval item so items don't contaminate each other
    client$chat$set_turns(list())
    tryCatch(
      codeagent(client, input),
      error = function(e) paste0("[Error] ", conditionMessage(e))
    )
  }
}

# ---------------------------------------------------------------------------
# Task
# ---------------------------------------------------------------------------

tool_use_task <- Task$new(
  dataset = tool_use_dataset,
  solver  = generate(codeagent_solver()),
  scorer  = detect_includes()
)
