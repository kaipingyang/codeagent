#' @title Multi-Agent Team Coordination
#' @description Run several independent sub-agent tasks in parallel and collect
#'   their results, mirroring Claude Code's team / parallel-agent dispatch. This
#'   uses the `mirai` package (CRAN) for parallel execution across background
#'   daemons -- we do not reimplement a scheduler. Each task runs a
#'   self-contained codeagent query in its own daemon, so the tasks must be
#'   independent (no shared mutable state). Results are returned in input order.
#'
#'   For dependent / interactive multi-agent work prefer the serial `agent_tool`
#'   (sub-agent) path; `team_run()` is for embarrassingly-parallel fan-out
#'   (e.g. "review these 5 files", "research these 3 questions").
#' @name team
#' @keywords internal
NULL

# Safe default worker count: respects cgroup / container CPU limits.
# parallel::detectCores() reports the HOST core count (e.g. 64) and ignores
# cgroup quotas, which would over-spawn heavy R daemons and risk OOM in a
# limited container. parallelly::availableCores() reads cgroup v1/v2, Slurm,
# etc. We cap at that; fall back to a conservative 4 if parallelly is absent.
.team_default_workers <- function(n_tasks) {
  cores <- tryCatch(
    if (requireNamespace("parallelly", quietly = TRUE))
      parallelly::availableCores() else 4L,
    error = function(e) 4L
  )
  as.integer(max(1L, min(n_tasks, cores)))
}

#' Run a set of independent tasks as a parallel agent team
#'
#' @param tasks Character vector of task prompts (one sub-agent per task).
#' @param model Character. Model spec each agent uses. Defaults to the
#'   `CODEAGENT_MODEL` env var or `"claude-sonnet-4-6"`.
#' @param n_workers Integer or NULL. Number of parallel daemons. Defaults to
#'   `min(length(tasks), parallelly::availableCores())` so it never exceeds the
#'   container's cgroup CPU quota (each daemon is a heavy R process).
#' @param permission_mode Character. Permission mode for each agent (default
#'   `"bypass"` since parallel agents cannot prompt interactively).
#' @param cwd Character. Working directory for each agent.
#' @return A list (same length/order as `tasks`), each element either the
#'   agent's text result or an `[Error] ...` string.
#' @export
team_run <- function(tasks, model = NULL, n_workers = NULL,
                     permission_mode = "bypass", cwd = getwd()) {
  if (!length(tasks)) return(list())
  if (!requireNamespace("mirai", quietly = TRUE))
    stop("team_run() requires the 'mirai' package.", call. = FALSE)

  model     <- model %||% Sys.getenv("CODEAGENT_MODEL", "claude-sonnet-4-6")
  n_workers <- if (is.null(n_workers)) .team_default_workers(length(tasks))
               else as.integer(min(n_workers, .team_default_workers(length(tasks))))
  base_url  <- Sys.getenv("CODEAGENT_BASE_URL", "")
  api_key   <- Sys.getenv("CODEAGENT_API_KEY", "")

  # Spin up daemons, ensure they are torn down on exit.
  mirai::daemons(n_workers)
  on.exit(mirai::daemons(0L), add = TRUE)

  # Worker function: build a fresh client in the daemon and run one query.
  run_one <- function(task, model, base_url, api_key, permission_mode, cwd) {
    Sys.setenv(CODEAGENT_BASE_URL = base_url, CODEAGENT_API_KEY = api_key,
               CODEAGENT_MODEL = model)
    tryCatch({
      client <- codeagent::codeagent_client(
        permission_mode = permission_mode, cwd = cwd, btw_groups = NULL)
      codeagent::codeagent(client, task)
    }, error = function(e) paste0("[Error] ", conditionMessage(e)))
  }

  m <- mirai::mirai_map(
    tasks,
    run_one,
    model = model, base_url = base_url, api_key = api_key,
    permission_mode = permission_mode, cwd = cwd
  )
  results <- tryCatch(m[], error = function(e)
    as.list(rep(paste0("[Error] team_run failed: ", conditionMessage(e)),
                length(tasks))))
  as.list(results)
}

#' Create the TeamRun tool
#'
#' Exposes [team_run()] to the model so it can fan out independent subtasks in
#' parallel and get all results back at once.
#'
#' @param model Character. Default model for team agents.
#' @param cwd Character. Working directory.
#' @return An `ellmer::tool()` object.
#' @keywords internal
team_run_tool <- function(model = NULL, cwd = getwd()) {
  force(model); force(cwd)
  ellmer::tool(
    fun = function(tasks, n_workers = NULL) {
      tk <- if (is.character(tasks)) as.list(tasks) else tasks
      tk <- unlist(lapply(tk, as.character))
      if (!length(tk))
        return(.tool_result2("[TeamRun] no tasks provided.", kind = "error",
                             icon = "people", title = "TeamRun -- empty"))
      results <- tryCatch(
        team_run(tk, model = model, n_workers = n_workers, cwd = cwd),
        error = function(e) as.list(paste0("[Error] ", conditionMessage(e))))
      # Assemble a readable combined result.
      parts <- vapply(seq_along(results), function(i)
        sprintf("### Task %d\n%s", i, as.character(results[[i]])),
        character(1))
      combined <- paste(parts, collapse = "\n\n")
      .tool_result2(combined, kind = "text", icon = "people",
                    title = sprintf("TeamRun (%d agents)", length(tk)),
                    markdown = combined,
                    payload = list(text = combined, lang = "markdown"))
    },
    description = paste0(
      "Run several INDEPENDENT subtasks in parallel, each handled by its own ",
      "sub-agent, and return all results together. Use for fan-out work where ",
      "tasks don't depend on each other (e.g. review N files, research N ",
      "questions). For dependent steps use a single sub-agent instead."
    ),
    arguments = list(
      tasks = ellmer::type_array(
        description = "Independent task prompts, one sub-agent per task.",
        items = ellmer::type_string("A self-contained task prompt.")),
      n_workers = ellmer::type_integer(
        "Max parallel agents (default min(#tasks, 4)).", required = FALSE)
    ),
    annotations = ellmer::tool_annotations(
      title = "TeamRun", read_only_hint = FALSE, open_world_hint = TRUE)
  )
}

#' Register the TeamRun tool on a chat
#'
#' @param chat An `ellmer::Chat` object.
#' @param model Character. Default model for team agents.
#' @param cwd Character. Working directory.
#' @return Invisibly `chat`.
#' @keywords internal
register_team_tool <- function(chat, model = NULL, cwd = getwd()) {
  if (!requireNamespace("mirai", quietly = TRUE)) return(invisible(chat))
  tryCatch(chat$register_tool(team_run_tool(model, cwd)),
           error = function(e) NULL)
  invisible(chat)
}
