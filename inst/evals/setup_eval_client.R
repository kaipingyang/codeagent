# inst/evals/setup_eval_client.R
# Source this before running evals to configure the solver chat.
# The solver chat is stored in options(codeagent.eval_chat) so individual
# task files can pick it up without repeating credentials.

library(codeagent)
library(ellmer)

solver_chat <- codeagent_client(
  permission_mode = "bypass",
  btw_groups = NULL,          # disable btw for cleaner/faster evals
  cwd = getwd()
)

options(codeagent.eval_chat = solver_chat)
message("Eval client ready: ", solver_chat$settings$model)
