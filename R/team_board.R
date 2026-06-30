#' @title Shared Task Board (multi-agent coordination)
#' @description A SQLite-backed task board that multiple agent workers (running
#'   in separate `mirai` daemon processes) can share to claim and complete work,
#'   plus a simple message log for inter-agent communication. Mirrors Claude
#'   Code's team coordination (TeamCreate / shared board / auto-claim /
#'   SendMessage).
#'
#'   Why SQLite, not the in-memory `.task_store` (`tools_task.R`): that store
#'   lives in one R process's memory and is invisible to mirai daemons. A SQLite
#'   file is shared across processes, and a claim is a single atomic
#'   `UPDATE ... WHERE owner IS NULL` so two workers never grab the same task.
#' @name team_board
#' @keywords internal
NULL

# Connect to a board database (created if missing).
.board_connect <- function(db_path) {
  if (!requireNamespace("DBI", quietly = TRUE) ||
      !requireNamespace("RSQLite", quietly = TRUE))
    cli::cli_abort(c(
      "The shared task board requires {.pkg DBI} and {.pkg RSQLite}.",
      "i" = "Install them with {.code install.packages(c('DBI','RSQLite'))}."
    ))
  con <- DBI::dbConnect(RSQLite::SQLite(), db_path)
  # Wait up to 5s on a locked db rather than erroring immediately.
  DBI::dbExecute(con, "PRAGMA busy_timeout = 5000")
  con
}

#' Create a new shared task board
#'
#' @param db_path Character. Path to the SQLite file. Defaults to a temp file.
#' @return Character. The `db_path` (pass it to the other board functions).
#' @export
board_create <- function(db_path = tempfile(fileext = ".sqlite")) {
  con <- .board_connect(db_path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS tasks (
      id      INTEGER PRIMARY KEY AUTOINCREMENT,
      prompt  TEXT    NOT NULL,
      owner   TEXT,
      status  TEXT    NOT NULL DEFAULT 'pending',
      result  TEXT,
      created TEXT
    )")
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS messages (
      id      INTEGER PRIMARY KEY AUTOINCREMENT,
      sender  TEXT,
      recipient TEXT,
      body    TEXT,
      created TEXT
    )")
  invisible(db_path)
}

#' Add a task to the board
#'
#' @param db_path Character. Board path.
#' @param prompt Character. The task prompt.
#' @return Integer. The new task id.
#' @export
board_add_task <- function(db_path, prompt) {
  con <- .board_connect(db_path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  DBI::dbExecute(con,
    "INSERT INTO tasks (prompt, status, created) VALUES (?, 'pending', ?)",
    params = list(as.character(prompt),
                  format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")))
  DBI::dbGetQuery(con, "SELECT last_insert_rowid() AS id")$id[[1L]]
}

#' Atomically claim the next pending task
#'
#' Uses a single `UPDATE ... WHERE owner IS NULL` so concurrent workers never
#' claim the same row.
#'
#' @param db_path Character. Board path.
#' @param worker_id Character. Identifier for the claiming worker.
#' @return A one-row data.frame (id, prompt) for the claimed task, or NULL if
#'   no pending task remains.
#' @export
board_claim <- function(db_path, worker_id) {
  con <- .board_connect(db_path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  n <- DBI::dbExecute(con,
    "UPDATE tasks SET owner = ?, status = 'claimed'
       WHERE id = (SELECT id FROM tasks WHERE owner IS NULL
                   ORDER BY id LIMIT 1)",
    params = list(as.character(worker_id)))
  if (n == 0L) return(NULL)
  DBI::dbGetQuery(con,
    "SELECT id, prompt FROM tasks WHERE owner = ? AND status = 'claimed'
       ORDER BY id DESC LIMIT 1",
    params = list(as.character(worker_id)))
}

#' Mark a claimed task complete with its result
#'
#' @param db_path Character. Board path.
#' @param id Integer. Task id.
#' @param result Character. The task result.
#' @return Invisibly TRUE.
#' @export
board_complete <- function(db_path, id, result) {
  con <- .board_connect(db_path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  DBI::dbExecute(con,
    "UPDATE tasks SET status = 'done', result = ? WHERE id = ?",
    params = list(as.character(result), as.integer(id)))
  invisible(TRUE)
}

#' Read the full board state
#'
#' @param db_path Character. Board path.
#' @return A data.frame of all tasks.
#' @export
board_status <- function(db_path) {
  con <- .board_connect(db_path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  DBI::dbGetQuery(con, "SELECT id, prompt, owner, status, result FROM tasks ORDER BY id")
}

# How many tasks are still unclaimed/incomplete.
.board_pending_count <- function(db_path) {
  con <- .board_connect(db_path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  DBI::dbGetQuery(con,
    "SELECT COUNT(*) AS n FROM tasks WHERE status != 'done'")$n[[1L]]
}

#' Post a message to the team message log
#'
#' @param db_path Character. Board path.
#' @param sender Character. Sender id.
#' @param body Character. Message body.
#' @param recipient Character or NULL. Target agent (NULL = broadcast).
#' @return Invisibly TRUE.
#' @export
board_send_message <- function(db_path, sender, body, recipient = NULL) {
  con <- .board_connect(db_path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  DBI::dbExecute(con,
    "INSERT INTO messages (sender, recipient, body, created) VALUES (?, ?, ?, ?)",
    params = list(as.character(sender),
                  if (is.null(recipient)) NA_character_ else as.character(recipient),
                  as.character(body),
                  format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")))
  invisible(TRUE)
}

#' Read messages from the team message log
#'
#' @param db_path Character. Board path.
#' @param recipient Character or NULL. If set, returns messages addressed to
#'   this recipient or broadcast (NULL recipient); otherwise all messages.
#' @return A data.frame of messages.
#' @export
board_messages <- function(db_path, recipient = NULL) {
  con <- .board_connect(db_path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  if (is.null(recipient))
    return(DBI::dbGetQuery(con, "SELECT sender, recipient, body, created FROM messages ORDER BY id"))
  DBI::dbGetQuery(con,
    "SELECT sender, recipient, body, created FROM messages
       WHERE recipient = ? OR recipient IS NULL ORDER BY id",
    params = list(as.character(recipient)))
}

# ---------------------------------------------------------------------------
# Coordinator: auto-claim workers over a shared board
# ---------------------------------------------------------------------------

#' Coordinate a team of agents over a shared task board
#'
#' Seeds a SQLite board with `tasks`, launches `n_workers` mirai daemons, and
#' has each worker loop: atomically claim the next task, run it as a codeagent
#' query, write the result back, repeat until the board is empty. Unlike
#' [team_run()] (a fixed fan-out where worker i always gets task i), this is a
#' work-stealing pool -- a fast worker claims more tasks, so uneven task sizes
#' are balanced automatically. Mirrors Claude Code's TeamCreate + auto-claim.
#'
#' @param tasks Character vector of task prompts.
#' @param model Character. Model spec for each worker.
#' @param n_workers Integer or NULL. Worker count; default cgroup-aware
#'   (`min(#tasks, parallelly::availableCores())`).
#' @param permission_mode Character. Permission mode for workers (default
#'   `"bypass"`; parallel workers cannot prompt).
#' @param cwd Character. Working directory for workers.
#' @param db_path Character. Board path (created if missing).
#' @return A data.frame: the final board (id, prompt, owner, status, result).
#' @export
team_coordinate <- function(tasks, model = NULL, n_workers = NULL,
                            permission_mode = "bypass", cwd = getwd(),
                            db_path = tempfile(fileext = ".sqlite")) {
  if (!length(tasks)) return(board_status(board_create(db_path)))
  if (!is.character(tasks))
    cli::cli_abort("{.arg tasks} must be a character vector of task prompts.")
  if (!requireNamespace("mirai", quietly = TRUE))
    cli::cli_abort(c(
      "{.fn team_coordinate} requires the {.pkg mirai} package.",
      "i" = "Install it with {.code install.packages('mirai')}."
    ))

  model     <- model %||% Sys.getenv("CODEAGENT_MODEL", "claude-sonnet-4-6")
  n_workers <- if (is.null(n_workers)) .team_default_workers(length(tasks))
               else as.integer(min(n_workers, .team_default_workers(length(tasks))))
  base_url  <- Sys.getenv("CODEAGENT_BASE_URL", "")
  api_key   <- Sys.getenv("CODEAGENT_API_KEY", "")

  # Seed the board.
  board_create(db_path)
  for (tk in tasks) board_add_task(db_path, tk)

  mirai::daemons(n_workers)
  on.exit(mirai::daemons(0L), add = TRUE)

  # Each worker loops: claim -> run -> complete, until the board drains.
  worker_loop <- function(worker_id, db_path, model, base_url, api_key,
                          permission_mode, cwd) {
    Sys.setenv(CODEAGENT_BASE_URL = base_url, CODEAGENT_API_KEY = api_key,
               CODEAGENT_MODEL = model)
    done <- 0L
    repeat {
      claimed <- tryCatch(codeagent::board_claim(db_path, worker_id),
                          error = function(e) NULL)
      if (is.null(claimed)) break
      res <- tryCatch({
        client <- codeagent::codeagent_client(
          permission_mode = permission_mode, cwd = cwd, btw_groups = NULL)
        codeagent::codeagent(client, claimed$prompt)
      }, error = function(e) paste0("[Error] ", conditionMessage(e)))
      codeagent::board_complete(db_path, claimed$id, res)
      codeagent::board_send_message(db_path, worker_id,
        paste0("completed task #", claimed$id), "coordinator")
      done <- done + 1L
    }
    done
  }

  worker_ids <- paste0("worker-", seq_len(n_workers))
  m <- mirai::mirai_map(
    worker_ids, worker_loop,
    db_path = db_path, model = model, base_url = base_url, api_key = api_key,
    permission_mode = permission_mode, cwd = cwd)
  tryCatch(m[], error = function(e) NULL)   # wait for all workers

  board_status(db_path)
}
