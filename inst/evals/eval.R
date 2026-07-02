# inst/evals/eval.R
# Main entry point: run all codeagent eval tasks with vitals.
#
# Usage:
#   source("inst/evals/setup_eval_client.R")   # configure solver chat
#   source("inst/evals/eval.R")                # run all tasks
#
# Results are written to .vitals/ (gitignored) and viewable with:
#   vitals::vitals_view()

library(vitals)

cat("Loading eval tasks...\n")
source("inst/evals/tasks/tool_use.R")
source("inst/evals/tasks/permissions.R")
source("inst/evals/tasks/data_explore.R")

cat("\nRunning evals (this calls the LLM -- may take a few minutes)...\n")

results <- list(
  tool_use    = tool_use_task$eval(log_dir = ".vitals"),
  permissions = permissions_task$eval(log_dir = ".vitals"),
  data_explore = data_explore_task$eval(log_dir = ".vitals")
)

cat("\n=== Eval results ===\n")
for (nm in names(results)) {
  r <- results[[nm]]
  score <- tryCatch(mean(r$scorer_output == "C", na.rm = TRUE), error = function(e) NA)
  cat(sprintf("  %-20s  %.0f%%\n", nm, score * 100))
}

cat("\nView full results: vitals::vitals_view()\n")

invisible(results)
