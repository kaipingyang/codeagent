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

.start_secure_mirai_daemons <- function(n, .compute = NULL) {
  launch_dir <- tempfile("codeagent-worker-startup-")
  dir.create(launch_dir, recursive = TRUE)
  on.exit(unlink(launch_dir, recursive = TRUE, force = TRUE), add = TRUE)
  clean_env <- c(
    R_ENVIRON = "", R_ENVIRON_USER = "",
    R_PROFILE = "", R_PROFILE_USER = "",
    HOME = launch_dir, R_USER = launch_dir,
    R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep),
    R_LIBS_USER = "", R_LIBS_SITE = ""
  )
  args <- list(n = n)
  if (!is.null(.compute)) args$.compute <- .compute
  withr::with_envvar(clean_env, withr::with_dir(
    launch_dir, do.call(mirai::daemons, args)))
}

.worker_backend <- function(model, provider, base_url = NULL,
                            api_key_env = "CODEAGENT_API_KEY",
                            effort_level = NULL) {
  scalar <- function(x, field, allow_empty = FALSE) {
    if (is.null(x) && allow_empty) return(NULL)
    if (!is.character(x) || length(x) != 1L || is.na(x) ||
        (!allow_empty && !nzchar(x)))
      stop("invalid worker backend ", field, call. = FALSE)
    x
  }
  api_key_env <- scalar(api_key_env, "api_key_env")
  if (!grepl("^[A-Za-z_][A-Za-z0-9_]*$", api_key_env))
    stop("invalid worker backend api_key_env", call. = FALSE)
  if (!is.null(effort_level) &&
      (!is.character(effort_level) || length(effort_level) != 1L ||
       !effort_level %in% c("low", "medium", "high", "xhigh")))
    stop("invalid worker backend effort_level", call. = FALSE)
  list(
    model = scalar(model, "model"),
    provider = sub("^chat_", "", scalar(provider, "provider")),
    base_url = scalar(base_url, "base_url", allow_empty = TRUE),
    api_key_env = api_key_env,
    effort_level = effort_level
  )
}

.worker_backend_from_settings <- function(settings) {
  provider <- settings$provider %||%
    if (!is.null(settings$base_url) && nzchar(settings$base_url))
      "openai_compatible" else "anthropic"
  .worker_backend(
    model = settings$model,
    provider = provider,
    base_url = settings$base_url,
    api_key_env = settings$api_key_env %||% "CODEAGENT_API_KEY",
    effort_level = settings$effort_level %||% settings$effortLevel
  )
}

.worker_security_context <- function(permission_mode = "dont_ask",
                                     rules = list(), tools = NULL,
                                     sandbox = NULL, cwd = getwd(),
                                     tool_config = list(),
                                     allowed_tools = NULL,
                                     allowed_tool_signatures = NULL,
                                     backend = NULL) {
  valid_modes <- unlist(PermissionMode, use.names = FALSE)
  if (!is.character(permission_mode) || length(permission_mode) != 1L ||
      !permission_mode %in% valid_modes)
    stop("invalid worker permission mode", call. = FALSE)
  if (!is.list(rules)) stop("worker permission rules must be a list", call. = FALSE)
  policy <- if (is.list(tools) && all(c("sets", "capabilities", "overrides") %in%
                                     names(tools))) tools
            else .resolve_tool_policy(list(tools = tools %||% list()))
  list(
    version = 2L,
    permission_mode = permission_mode,
    rules = rules,
    tools = policy,
    sandbox = sandbox %||% list(enabled = FALSE, allow_network = TRUE),
    cwd = .canonical_security_path(cwd, cwd, allow_missing = FALSE),
    tool_config = list(
      file_tools = tool_config$file_tools %||% "core",
      btw_groups = tool_config$btw_groups %||% character(),
      btw_all_groups = isTRUE(tool_config$btw_all_groups),
      explore_data = isTRUE(tool_config$explore_data),
      rag = isTRUE(tool_config$rag)
    ),
    allowed_tools = if (is.null(allowed_tools)) NULL
                    else unique(as.character(allowed_tools)),
    allowed_tool_signatures = allowed_tool_signatures %||% list(),
    backend = if (is.null(backend)) NULL else do.call(
      .worker_backend,
      backend[intersect(names(backend), names(formals(.worker_backend)))])
  )
}

.worker_security_context_from_settings <- function(settings, chat = NULL) {
  groups <- settings$btw_groups
  live_tools <- if (is.null(chat)) list() else
    tryCatch(chat$get_tools(), error = function(e) list())
  .worker_security_context(
    permission_mode = settings$permission_mode %||% "default",
    rules = settings$rules %||% list(),
    tools = .resolve_tool_policy(settings),
    sandbox = settings$sandbox,
    cwd = settings$cwd %||% getwd(),
    tool_config = list(
      file_tools = .resolve_file_tools(settings),
      btw_groups = groups %||% character(),
      btw_all_groups = is.null(groups),
      explore_data = !isFALSE(settings$explore_data),
      rag = isTRUE(settings$rag) ||
        (is.list(settings$rag) && isTRUE(settings$rag$enabled))
    ),
    allowed_tools = if (is.null(chat)) NULL else .tool_names(live_tools),
    allowed_tool_signatures = if (is.null(chat)) list()
                              else .tool_signatures(live_tools),
    backend = settings$worker_backend
  )
}

.worker_security_context_json <- function(context) {
  context <- do.call(.worker_security_context, context[
    intersect(names(context), names(formals(.worker_security_context)))])
  jsonlite::toJSON(context, auto_unbox = TRUE, null = "null")
}

.worker_client_from_json <- function(model, context_json, cwd = NULL,
                                     trusted_cwd_override = FALSE) {
  context <- tryCatch(
    jsonlite::fromJSON(context_json, simplifyVector = FALSE),
    error = function(e) stop("worker security context could not be restored",
                             call. = FALSE)
  )
  if (!as.integer(context$version) %in% c(1L, 2L))
    stop("unsupported worker security context", call. = FALSE)
  worker_cwd <- context$cwd
  if (isTRUE(trusted_cwd_override) && !is.null(cwd))
    worker_cwd <- cwd
  context <- .worker_security_context(
    permission_mode = context$permission_mode,
    rules = context$rules,
    tools = context$tools,
    sandbox = context$sandbox,
    cwd = worker_cwd,
    tool_config = context$tool_config,
    allowed_tools = context$allowed_tools,
    allowed_tool_signatures = context$allowed_tool_signatures,
    backend = context$backend
  )
  settings <- .CODEAGENT_DEFAULTS
  backend <- context$backend
  if (is.null(backend)) {
    settings$model <- model
    settings$base_url <- Sys.getenv("CODEAGENT_BASE_URL", "")
  } else {
    settings$model <- backend$model
    settings$provider <- backend$provider
    settings$base_url <- backend$base_url
    settings$api_key_env <- backend$api_key_env
    settings$effort_level <- backend$effort_level
  }
  settings$permission_mode <- context$permission_mode
  settings$rules <- context$rules
  settings$tools <- context$tools
  settings$sandbox <- context$sandbox
  settings$cwd <- context$cwd
  settings$file_tools <- context$tool_config$file_tools
  settings$btw_groups <- if (isTRUE(context$tool_config$btw_all_groups))
    NULL else unlist(context$tool_config$btw_groups, use.names = FALSE)
  settings$explore_data <- isTRUE(context$tool_config$explore_data)
  settings$rag <- isTRUE(context$tool_config$rag)
  settings$background_agents <- FALSE
  settings$delegation_tools <- FALSE
  settings$hooks <- list()
  settings$hooks_registry <- NULL
  settings$mcp_config <- NULL
  settings$data_shield <- NULL
  settings$data_shield_engine <- NULL
  chat <- .make_chat(settings, context$cwd)
  .register_all_tools(chat, settings, ask_fn = NULL)
  if (!is.null(context$allowed_tools)) {
    live <- tryCatch(chat$get_tools(), error = function(e)
      stop("worker tool snapshot could not be verified", call. = FALSE))
    live <- .filter_verified_worker_tools(live, context)
    chat$set_tools(live)
    if (any(!.tool_names(chat$get_tools()) %in% context$allowed_tools))
      stop("worker tool set exceeds parent capabilities", call. = FALSE)
  }
  .new_client(chat, settings, data_shield = NULL)
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
#'   `"dont_ask"` since parallel agents cannot prompt interactively -- NOT
#'   "bypass", so user-defined deny rules are still honoured).
#' @param cwd Character. Working directory for each agent.
#' @param parent_rules List. Permission rules inherited from the parent agent.
#' @param parent_policy List. Tool capability policies inherited from parent.
#' @param security_context Internal immutable parent security snapshot. When
#'   supplied it takes precedence over the legacy permission arguments.
#' @return A list (same length/order as `tasks`), each element either the
#'   agent's text result or an `[Error] ...` string.
#' @export
team_run <- function(tasks, model = NULL, n_workers = NULL,
                     permission_mode = "dont_ask", cwd = getwd(),
                     parent_rules = NULL, parent_policy = NULL,
                     security_context = NULL) {
  if (!length(tasks)) return(list())
  if (!is.character(tasks))
    cli::cli_abort("{.arg tasks} must be a character vector of task prompts, not {.cls {class(tasks)[1]}}.")
  if (!requireNamespace("mirai", quietly = TRUE))
    cli::cli_abort(c(
      "{.fn team_run} requires the {.pkg mirai} package.",
      "i" = "Install it with {.code install.packages('mirai')}."
    ))

  security_context <- security_context %||% .worker_security_context(
    permission_mode, parent_rules %||% list(), parent_policy, cwd = cwd)
  backend <- security_context$backend %||% NULL
  model <- backend$model %||% model %||%
    Sys.getenv("CODEAGENT_MODEL", "claude-sonnet-4-6")
  n_workers <- if (is.null(n_workers)) .team_default_workers(length(tasks))
               else as.integer(min(n_workers, .team_default_workers(length(tasks))))
  base_url  <- if (is.null(backend)) Sys.getenv("CODEAGENT_BASE_URL", "") else ""
  api_key   <- if (is.null(backend)) Sys.getenv("CODEAGENT_API_KEY", "") else ""
  security_json <- .worker_security_context_json(security_context)

  # Worker function: build a fresh client and run one query.
  # Uses parent's permission mode and rules -- never auto-bypasses.
  run_one <- function(task, model, base_url, api_key, cwd, security_json,
                      legacy_env) {
    if (isTRUE(legacy_env))
      Sys.setenv(CODEAGENT_BASE_URL = base_url, CODEAGENT_API_KEY = api_key,
                 CODEAGENT_MODEL = model)
    else
      Sys.setenv(CODEAGENT_MODEL = model)
    tryCatch({
      client <- codeagent:::.worker_client_from_json(model, security_json)
      codeagent::codeagent(client, task)
    }, error = function(e) paste0("[Error] ", conditionMessage(e)))
  }

  # Run each task in its own mirai daemon. mirai_map preserves input order and
  # collects all results; run_one takes everything via arguments so it
  # serialises cleanly to the worker processes.
  .start_secure_mirai_daemons(n_workers)
  on.exit(mirai::daemons(0L), add = TRUE)
  m <- mirai::mirai_map(
    tasks, run_one,
    .args = list(model = model, base_url = base_url, api_key = api_key,
                 cwd = cwd, security_json = security_json,
                 legacy_env = is.null(backend))
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
#' @param parent_rules List. Permission rules inherited from the parent.
#' @param parent_policy List. Tool capability policies inherited from parent.
#' @param security_context Internal immutable parent security snapshot.
#' @return An `ellmer::tool()` object.
#' @keywords internal
team_run_tool <- function(model = NULL, cwd = getwd(),
                           parent_rules = NULL, parent_policy = NULL,
                           security_context = NULL) {
  force(model); force(cwd); force(parent_rules); force(parent_policy)
  force(security_context)
  ellmer::tool(
    name = "TeamRun",
    fun = function(tasks, n_workers = NULL) {
      tk <- if (is.character(tasks)) as.list(tasks) else tasks
      tk <- unlist(lapply(tk, as.character))
      if (!length(tk))
        return(.artifact_tool_result("[TeamRun] no tasks provided.", kind = "error",
                             icon = "people", title = "TeamRun -- empty"))
      results <- tryCatch(
        team_run(tk, model = model, n_workers = n_workers, cwd = cwd,
                 parent_rules = parent_rules, parent_policy = parent_policy,
                 security_context = security_context),
        error = function(e) as.list(paste0("[Error] ", conditionMessage(e))))
      # Assemble a readable combined result.
      parts <- vapply(seq_along(results), function(i)
        sprintf("### Task %d\n%s", i, as.character(results[[i]])),
        character(1))
      combined <- paste(parts, collapse = "\n\n")
      .artifact_tool_result(combined, kind = "text", icon = "people",
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
#' @param parent_rules List. Permission rules inherited from parent.
#' @param parent_policy List. Tool capability policies inherited from parent.
#' @param security_context Internal immutable parent security snapshot.
#' @return Invisibly `chat`.
#' @keywords internal
register_team_tool <- function(chat, model = NULL, cwd = getwd(),
                                parent_rules = NULL, parent_policy = NULL,
                                security_context = NULL) {
  if (!requireNamespace("mirai", quietly = TRUE)) return(invisible(chat))
  tryCatch(chat$register_tool(team_run_tool(model, cwd,
                              parent_rules = parent_rules,
                              parent_policy = parent_policy,
                              security_context = security_context)),
           error = function(e) NULL)
  # Coordinated work-stealing team (shared SQLite board) -- needs DBI/RSQLite.
  if (requireNamespace("DBI", quietly = TRUE) &&
      requireNamespace("RSQLite", quietly = TRUE))
    tryCatch(chat$register_tool(team_coordinate_tool(
      model, cwd, security_context = security_context)),
             error = function(e) NULL)
  invisible(chat)
}

#' Create the TeamCoordinate tool
#'
#' Exposes [team_coordinate()] so the model can run a work-stealing team over a
#' shared board (uneven task sizes auto-balanced), distinct from TeamRun's fixed
#' fan-out.
#'
#' @param model Character. Default model for team agents.
#' @param cwd Character. Working directory.
#' @param security_context Internal immutable parent security snapshot.
#' @return An `ellmer::tool()` object.
#' @keywords internal
team_coordinate_tool <- function(model = NULL, cwd = getwd(),
                                 security_context = NULL) {
  force(model); force(cwd); force(security_context)
  ellmer::tool(
    name = "TeamCoordinate",
    fun = function(tasks, n_workers = NULL) {
      tk <- if (is.character(tasks)) as.list(tasks) else tasks
      tk <- unlist(lapply(tk, as.character))
      if (!length(tk))
        return(.artifact_tool_result("[TeamCoordinate] no tasks provided.", kind = "error",
                             icon = "people", title = "TeamCoordinate -- empty"))
      board <- tryCatch(
        team_coordinate(tk, model = model, n_workers = n_workers, cwd = cwd,
                        security_context = security_context),
        error = function(e) NULL)
      if (is.null(board))
        return(.artifact_tool_result("[TeamCoordinate] failed.", kind = "error",
                             icon = "people", title = "TeamCoordinate -- error"))
      parts <- vapply(seq_len(nrow(board)), function(i)
        sprintf("### Task #%s (%s)\n%s", board$id[i], board$status[i],
                as.character(board$result[i])),
        character(1))
      combined <- paste(parts, collapse = "\n\n")
      .artifact_tool_result(combined, kind = "text", icon = "people",
                    title = sprintf("TeamCoordinate (%d tasks)", nrow(board)),
                    markdown = combined,
                    payload = list(text = combined, lang = "markdown"))
    },
    description = paste0(
      "Run a work-stealing team of agents over a shared task board: each worker ",
      "repeatedly claims the next pending task, completes it, and claims again, ",
      "until all are done. Use when tasks have UNEVEN sizes (a fast worker takes ",
      "more) -- unlike TeamRun's fixed one-task-per-worker fan-out. Tasks must be ",
      "independent."
    ),
    arguments = list(
      tasks = ellmer::type_array(
        description = "Independent task prompts to distribute across the team.",
        items = ellmer::type_string("A self-contained task prompt.")),
      n_workers = ellmer::type_integer(
        "Max parallel workers (default cgroup-aware).", required = FALSE)
    ),
    annotations = ellmer::tool_annotations(
      title = "TeamCoordinate", read_only_hint = FALSE, open_world_hint = TRUE)
  )
}
