#' @title Task Management Tools
#' @description TaskCreate, TaskGet, TaskUpdate, TaskList tools for codeagent.
#'   Tasks are stored in a per-session environment (created fresh per
#'   `register_task_tools()` call) so concurrent agents do not share state.
#' @name tools_task
#' @keywords internal
NULL

# ---------------------------------------------------------------------------
# Per-session task store factory
# ---------------------------------------------------------------------------

# Create a fresh, isolated task store environment.  Called once per
# codeagent_client() / register_task_tools() invocation so that parallel
# agents (team.R) each get their own store rather than sharing a single
# package-level global environment.
.new_task_store <- function() {
  store <- new.env(parent = emptyenv())
  store$tasks   <- list()
  store$next_id <- 1L
  store
}

# Accessors -- all take an explicit store argument.
.task_new_id <- function(store) {
  id <- as.character(store$next_id)
  store$next_id <- store$next_id + 1L
  id
}

.task_get <- function(id, store) store$tasks[[id]]

.task_set <- function(id, task, store) {
  store$tasks[[id]] <- task
  invisible(NULL)
}

.task_list_all <- function(store) store$tasks

.task_reset <- function(store) {
  store$tasks   <- list()
  store$next_id <- 1L
}

# ---------------------------------------------------------------------------
# TaskCreate tool
# ---------------------------------------------------------------------------

#' Create the TaskCreate tool
#'
#' @param store Environment. Per-session task store from `.new_task_store()`.
#' @return An `ellmer::tool()` object.
#' @keywords internal
task_create_tool <- function(store) {
  force(store)
  ellmer::tool(
    fun = function(subject, description, active_form = NULL) {
      id   <- .task_new_id(store)
      task <- list(
        id          = id,
        subject     = subject,
        description = description,
        active_form = active_form,
        status      = "pending",
        owner       = NULL,
        blocks      = character(0),
        blocked_by  = character(0),
        created_at  = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
      )
      .task_set(id, task, store)
      paste0("Created task #", id, ": ", subject)
    },
    description = "Create a new pending task in the task list.",
    arguments   = list(
      subject     = ellmer::type_string(
        "Brief task title (imperative form).", required = TRUE),
      description = ellmer::type_string(
        "What needs to be done.", required = TRUE),
      active_form = ellmer::type_string(
        "Present-continuous form shown when in_progress (e.g. 'Running tests').",
        required = FALSE)
    ),
    annotations = ellmer::tool_annotations(
      title          = "TaskCreate",
      read_only_hint = FALSE,
      destructive_hint = FALSE
    )
  )
}

# ---------------------------------------------------------------------------
# TaskGet tool
# ---------------------------------------------------------------------------

#' Create the TaskGet tool
#'
#' @param store Environment. Per-session task store from `.new_task_store()`.
#' @return An `ellmer::tool()` object.
#' @keywords internal
task_get_tool <- function(store) {
  force(store)
  ellmer::tool(
    fun = function(task_id) {
      task <- .task_get(as.character(task_id), store)
      if (is.null(task)) return(paste0("[Error] Task not found: #", task_id))
      lines <- c(
        paste0("Task #", task$id, ": ", task$subject),
        paste0("Status: ", task$status),
        paste0("Description: ", task$description)
      )
      if (!is.null(task$owner))        lines <- c(lines, paste0("Owner: ", task$owner))
      if (length(task$blocks) > 0)     lines <- c(lines, paste0("Blocks: #",   paste(task$blocks,     collapse = ", #")))
      if (length(task$blocked_by) > 0) lines <- c(lines, paste0("BlockedBy: #", paste(task$blocked_by, collapse = ", #")))
      paste(lines, collapse = "\n")
    },
    description = "Get full details of a task by ID.",
    arguments   = list(
      task_id = ellmer::type_string("The task ID.", required = TRUE)
    ),
    annotations = ellmer::tool_annotations(
      title          = "TaskGet",
      read_only_hint = TRUE
    )
  )
}

# ---------------------------------------------------------------------------
# TaskUpdate tool
# ---------------------------------------------------------------------------

#' Create the TaskUpdate tool
#'
#' @param store Environment. Per-session task store from `.new_task_store()`.
#' @return An `ellmer::tool()` object.
#' @keywords internal
task_update_tool <- function(store) {
  force(store)
  ellmer::tool(
    fun = function(task_id, status = NULL, subject = NULL,
                   description = NULL, owner = NULL,
                   add_blocks = NULL, add_blocked_by = NULL) {
      id   <- as.character(task_id)
      task <- .task_get(id, store)
      if (is.null(task)) return(paste0("[Error] Task not found: #", task_id))

      if (!is.null(status))      task$status      <- status
      if (!is.null(subject))     task$subject      <- subject
      if (!is.null(description)) task$description  <- description
      if (!is.null(owner))       task$owner        <- owner

      if (!is.null(add_blocks))
        task$blocks <- unique(c(task$blocks, as.character(add_blocks)))
      if (!is.null(add_blocked_by))
        task$blocked_by <- unique(c(task$blocked_by, as.character(add_blocked_by)))

      if (identical(status, "deleted")) {
        store$tasks[[id]] <- NULL
        return(paste0("Deleted task #", task_id))
      }

      .task_set(id, task, store)
      paste0("Updated task #", id, " (", task$subject, "): status=", task$status)
    },
    description = paste0(
      "Update a task's status, subject, description, owner, or dependencies. ",
      "Set status to 'deleted' to remove a task."
    ),
    arguments   = list(
      task_id        = ellmer::type_string("The task ID to update.", required = TRUE),
      status         = ellmer::type_enum(
        values      = c("pending", "in_progress", "completed", "deleted"),
        description = "New status.",
        required    = FALSE),
      subject        = ellmer::type_string("New task title.", required = FALSE),
      description    = ellmer::type_string("New description.", required = FALSE),
      owner          = ellmer::type_string("New owner.", required = FALSE),
      add_blocks     = ellmer::type_array(
        items       = ellmer::type_string(),
        description = "Task IDs that this task blocks.",
        required    = FALSE),
      add_blocked_by = ellmer::type_array(
        items       = ellmer::type_string(),
        description = "Task IDs that must complete before this one.",
        required    = FALSE)
    ),
    annotations = ellmer::tool_annotations(
      title            = "TaskUpdate",
      read_only_hint   = FALSE,
      destructive_hint = FALSE
    )
  )
}

# ---------------------------------------------------------------------------
# TaskList tool
# ---------------------------------------------------------------------------

#' Create the TaskList tool
#'
#' @param store Environment. Per-session task store from `.new_task_store()`.
#' @return An `ellmer::tool()` object.
#' @keywords internal
task_list_tool <- function(store) {
  force(store)
  ellmer::tool(
    fun = function() {
      tasks <- .task_list_all(store)
      tasks <- tasks[!vapply(tasks, is.null, logical(1))]
      if (length(tasks) == 0L) return("No tasks.")
      lines <- vapply(tasks, function(t) {
        blocked <- if (length(t$blocked_by) > 0)
          paste0(" [blocked by #", paste(t$blocked_by, collapse=", #"), "]")
        else ""
        paste0("#", t$id, " [", t$status, "] ", t$subject, blocked)
      }, character(1))
      paste(lines, collapse = "\n")
    },
    description = "List all tasks with their IDs, status, and subjects.",
    arguments   = list(),
    annotations = ellmer::tool_annotations(
      title          = "TaskList",
      read_only_hint = TRUE
    )
  )
}

# ---------------------------------------------------------------------------
# Register all task tools
# ---------------------------------------------------------------------------

#' Register task management tools to an ellmer Chat object
#'
#' Creates a fresh per-session task store and registers TaskCreate, TaskGet,
#' TaskUpdate, TaskList tools. Each call gets an isolated store so parallel
#' agents do not collide on task IDs.
#'
#' @param chat An `ellmer::Chat` object.
#' @return Invisibly returns `chat`.
#' @export
register_task_tools <- function(chat) {
  store <- .new_task_store()
  chat$register_tool(task_create_tool(store))
  chat$register_tool(task_get_tool(store))
  chat$register_tool(task_update_tool(store))
  chat$register_tool(task_list_tool(store))
  invisible(chat)
}
