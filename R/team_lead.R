#' @title LLM-lead autonomous coordinator
#' @description A bounded "lead" loop that faithfully ports Claude Code's
#'   COORDINATOR_MODE: a lead model decomposes a high-level goal into a task DAG,
#'   a work-stealing team ([team_coordinate()]) auto-claims and runs it, then the
#'   lead reviews the results and either declares the goal done or adds a
#'   follow-up round -- repeating up to `max_rounds`.
#'
#'   The three LLM/execution steps are injectable (`decompose_fn`, `review_fn`,
#'   `coordinate_fn`) so the loop control is unit-testable without a live model;
#'   the defaults are ellmer structured-output calls + the real board.
#' @name team_lead
#' @keywords internal
NULL

# Parse a structured decomposition/review object into team_coordinate() args.
# Accepts `obj$tasks` as either a data.frame (one row per subtask) or a list of
# lists, each with `description` (+ aliases) and `depends_on` (int vector or a
# comma/semicolon-separated string of 1-based indices). PURE.
.parse_decomposition <- function(obj) {
  tasks_obj <- obj$tasks
  if (is.null(tasks_obj)) return(list(tasks = character(0), blocked_by = list()))
  rows <- if (is.data.frame(tasks_obj)) {
    lapply(seq_len(nrow(tasks_obj)), function(i) as.list(tasks_obj[i, , drop = FALSE]))
  } else tasks_obj
  descs <- vapply(rows, function(r) {
    as.character(r$description %||% r$prompt %||% r$task %||% "")[1]
  }, character(1))
  blocked <- lapply(rows, function(r) {
    d <- r$depends_on %||% r$blocked_by %||% ""
    if (is.numeric(d)) return(as.integer(d[!is.na(d)]))
    parts <- trimws(strsplit(as.character(d)[1] %||% "", "[,;]")[[1]])
    as.integer(parts[nzchar(parts) & grepl("^[0-9]+$", parts)])
  })
  keep <- nzchar(trimws(descs))
  list(tasks = descs[keep], blocked_by = blocked[keep])
}

# Loop control: keep going only if under the round cap, the lead hasn't declared
# done, and it actually proposed follow-up tasks. PURE.
.lead_should_continue <- function(round, max_rounds, review) {
  if (round >= max_rounds) return(FALSE)
  if (isTRUE(review$done)) return(FALSE)
  length(review$plan$tasks %||% character(0)) > 0L
}

# Build a lead chat from env/model (openai-compatible when CODEAGENT_BASE_URL set).
.lead_chat <- function(model, cwd) {
  base_url <- Sys.getenv("CODEAGENT_BASE_URL", "")
  .make_chat(list(
    model       = model %||% Sys.getenv("CODEAGENT_MODEL", "claude-sonnet-4-6"),
    base_url    = base_url,
    provider    = if (nzchar(base_url)) "openai_compatible" else NULL,
    api_key_env = "CODEAGENT_API_KEY"), cwd)
}

# The structured type shared by decompose + review: an array of {description,
# depends_on} subtasks.
.lead_task_type <- function(desc) {
  ellmer::type_array(
    ellmer::type_object(
      description = ellmer::type_string("A concrete, independently-runnable subtask."),
      depends_on  = ellmer::type_string(
        "Comma-separated 1-based indices of earlier subtasks that must finish first; empty if none.")
    ),
    description = desc)
}

.default_lead_decompose <- function(goal, model, cwd) {
  chat <- .lead_chat(model, cwd)
  type <- ellmer::type_object(tasks = .lead_task_type(
    "Ordered subtasks that together accomplish the goal."))
  out <- chat$chat_structured(paste0(
    "Break this goal into a minimal set of concrete subtasks that a team of ",
    "coding agents can run in parallel. Note dependencies between subtasks. ",
    "Goal:\n", goal), type = type)
  .parse_decomposition(out)
}

.default_lead_review <- function(goal, board, model, cwd) {
  chat <- .lead_chat(model, cwd)
  summ <- if (is.null(board) || !nrow(board)) "(no tasks run yet)" else
    paste(sprintf("- [%s] %s => %s", board$status, board$prompt,
                  substr(as.character(board$result %||% ""), 1L, 200L)),
          collapse = "\n")
  type <- ellmer::type_object(
    done  = ellmer::type_boolean(
      "TRUE if the goal is fully accomplished and no further subtasks are needed."),
    tasks = .lead_task_type("Follow-up subtasks (leave empty when done = TRUE)."))
  out <- chat$chat_structured(paste0(
    "Goal:\n", goal, "\n\nCompleted so far:\n", summ,
    "\n\nIs the goal fully done? If not, list ONLY the follow-up subtasks still needed."),
    type = type)
  list(done = isTRUE(out$done), plan = .parse_decomposition(out))
}

#' Run a goal through an LLM-lead coordinator (decompose -> team -> review loop)
#'
#' @param goal Character(1). The high-level objective.
#' @param model Character. Model spec for the lead and the workers.
#' @param cwd Character. Working directory.
#' @param max_rounds Integer. Maximum decompose/review rounds (default 3).
#' @param n_workers,permission_mode,worktree Passed to [team_coordinate()].
#' @param decompose_fn,review_fn,coordinate_fn Injectable steps (for testing);
#'   default to ellmer structured calls + the real board.
#' @return A data.frame: every task run across all rounds (with a `round` column).
#' @export
team_lead <- function(goal, model = NULL, cwd = getwd(), max_rounds = 3L,
                      n_workers = NULL, permission_mode = "bypass",
                      worktree = FALSE, decompose_fn = NULL, review_fn = NULL,
                      coordinate_fn = NULL) {
  if (!is.character(goal) || length(goal) != 1L || !nzchar(goal))
    cli::cli_abort("{.arg goal} must be a non-empty string.")
  max_rounds    <- max(1L, as.integer(max_rounds))
  decompose_fn  <- decompose_fn  %||% .default_lead_decompose
  review_fn     <- review_fn     %||% .default_lead_review
  coordinate_fn <- coordinate_fn %||% function(tasks, blocked_by) {
    team_coordinate(tasks, blocked_by = blocked_by, model = model,
                    n_workers = n_workers, permission_mode = permission_mode,
                    worktree = worktree, cwd = cwd)
  }

  plan   <- decompose_fn(goal, model, cwd)
  rounds <- list()
  round  <- 0L
  repeat {
    if (!length(plan$tasks)) break
    round <- round + 1L
    board <- coordinate_fn(plan$tasks, plan$blocked_by)
    if (!is.null(board) && nrow(board)) board$round <- round
    rounds[[length(rounds) + 1L]] <- board

    review <- tryCatch(review_fn(goal, board, model, cwd),
                       error = function(e) list(done = TRUE, plan = list(tasks = character(0))))
    if (!.lead_should_continue(round, max_rounds, review)) break
    plan <- review$plan
  }
  boards <- Filter(function(b) !is.null(b) && nrow(b) > 0L, rounds)
  if (!length(boards)) return(board_status(board_create()))
  do.call(rbind, boards)
}
