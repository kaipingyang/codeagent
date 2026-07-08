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
      id         INTEGER PRIMARY KEY AUTOINCREMENT,
      prompt     TEXT    NOT NULL,
      owner      TEXT,
      status     TEXT    NOT NULL DEFAULT 'pending',
      result     TEXT,
      created    TEXT,
      claimed_at TEXT
    )")
  # Task dependency edges (DAG): `task_id` is blocked until `blocker_id` is done.
  DBI::dbExecute(con, "
    CREATE TABLE IF NOT EXISTS deps (
      task_id    INTEGER NOT NULL,
      blocker_id INTEGER NOT NULL,
      PRIMARY KEY (task_id, blocker_id)
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
#' @param blocked_by Integer vector. Task ids that must be `done` before this
#'   task can be claimed (DAG edges). Default none. Blockers must already exist
#'   on the board (a new task cannot create a cycle by construction).
#' @return Integer. The new task id.
#' @export
board_add_task <- function(db_path, prompt, blocked_by = integer(0)) {
  con <- .board_connect(db_path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  DBI::dbExecute(con,
    "INSERT INTO tasks (prompt, status, created) VALUES (?, 'pending', ?)",
    params = list(as.character(prompt),
                  format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")))
  id <- DBI::dbGetQuery(con, "SELECT last_insert_rowid() AS id")$id[[1L]]
  blocked_by <- as.integer(blocked_by[!is.na(blocked_by)])
  for (b in blocked_by) {
    DBI::dbExecute(con,
      "INSERT OR IGNORE INTO deps (task_id, blocker_id) VALUES (?, ?)",
      params = list(as.integer(id), as.integer(b)))
  }
  id
}

#' Atomically claim the next claimable task (dependency-aware)
#'
#' Runs inside a `BEGIN IMMEDIATE` transaction (SQLite serialises writers) and
#' claims the lowest-id task that is unowned, `pending`, and has **no
#' unfinished blocker** (all its `deps` blockers are `done`). With no deps this
#' is exactly the old FIFO claim (backward compatible). Returns `NULL` when
#' nothing is currently claimable -- which may mean "all done" OR "remaining
#' tasks are still blocked", so a worker should back off and retry rather than
#' exit (see `team_coordinate`).
#'
#' @param db_path Character. Board path.
#' @param worker_id Character. Identifier for the claiming worker.
#' @return A one-row data.frame (id, prompt) for the claimed task, or NULL.
#' @export
board_claim <- function(db_path, worker_id) {
  con <- .board_connect(db_path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  DBI::dbExecute(con, "BEGIN IMMEDIATE")
  tryCatch({
    elig <- DBI::dbGetQuery(con,
      "SELECT t.id, t.prompt FROM tasks t
         WHERE t.owner IS NULL AND t.status = 'pending'
           AND NOT EXISTS (
             SELECT 1 FROM deps d JOIN tasks b ON b.id = d.blocker_id
               WHERE d.task_id = t.id AND b.status != 'done')
         ORDER BY t.id LIMIT 1")
    if (nrow(elig) > 0L) {
      DBI::dbExecute(con,
        "UPDATE tasks SET owner = ?, status = 'claimed', claimed_at = ?
           WHERE id = ? AND owner IS NULL",
        params = list(as.character(worker_id),
                      format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
                      as.integer(elig$id[[1L]])))
    }
    DBI::dbExecute(con, "COMMIT")
    if (nrow(elig) > 0L) elig[, c("id", "prompt")] else NULL
  }, error = function(e) {
    tryCatch(DBI::dbExecute(con, "ROLLBACK"), error = function(e2) NULL)
    NULL
  })
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
# Pure DAG helpers (no DB / no Shiny -- unit-testable)
# ---------------------------------------------------------------------------

# Topologically sort task ids given dependency edges. `deps` is a data.frame
# with `task_id` (blocked) + `blocker_id` (prerequisite). Kahn's algorithm;
# errors on a cycle (which would otherwise deadlock the board). Edges whose
# endpoints are not in `ids` are ignored. PURE.
.task_toposort <- function(ids, deps) {
  ids <- as.integer(ids)
  key <- as.character(ids)
  indeg <- stats::setNames(integer(length(ids)), key)
  adj   <- stats::setNames(vector("list", length(ids)), key)   # blocker -> blocked[]
  if (!is.null(deps) && nrow(deps) > 0L) {
    for (i in seq_len(nrow(deps))) {
      t <- as.character(deps$task_id[i])
      b <- as.character(deps$blocker_id[i])
      if (!(t %in% key) || !(b %in% key)) next   # ignore edges outside `ids`
      indeg[t] <- indeg[t] + 1L
      adj[[b]] <- c(adj[[b]], t)
    }
  }
  queue <- key[indeg == 0L]
  order <- integer(0)
  while (length(queue)) {
    n <- queue[[1L]]; queue <- queue[-1L]
    order <- c(order, as.integer(n))
    for (m in adj[[n]]) {
      indeg[m] <- indeg[m] - 1L
      if (indeg[m] == 0L) queue <- c(queue, m)
    }
  }
  if (length(order) != length(ids))
    stop("Task dependency cycle detected.", call. = FALSE)
  order
}

# Which tasks are claimable right now: unowned + pending + all blockers done.
# `tasks_df` needs columns id/owner/status; `deps_df` needs task_id/blocker_id.
# PURE (mirrors the SQL in board_claim, for UI + tests).
.claimable_ids <- function(tasks_df, deps_df) {
  if (is.null(tasks_df) || nrow(tasks_df) == 0L) return(integer(0))
  done <- as.integer(tasks_df$id[tasks_df$status == "done"])
  cand <- as.integer(tasks_df$id[is.na(tasks_df$owner) & tasks_df$status == "pending"])
  if (!length(cand)) return(integer(0))
  has_deps <- !is.null(deps_df) && nrow(deps_df) > 0L
  ok <- vapply(cand, function(tid) {
    if (!has_deps) return(TRUE)
    blockers <- as.integer(deps_df$blocker_id[deps_df$task_id == tid])
    all(blockers %in% done)
  }, logical(1))
  cand[ok]
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
