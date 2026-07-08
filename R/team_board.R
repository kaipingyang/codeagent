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

# Record a DAG edge: `task_id` is blocked until `blocker_id` is done. Used by
# team_coordinate's two-pass seeding (add all tasks, then wire deps by index).
.board_add_dep <- function(db_path, task_id, blocker_id) {
  con <- .board_connect(db_path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  DBI::dbExecute(con,
    "INSERT OR IGNORE INTO deps (task_id, blocker_id) VALUES (?, ?)",
    params = list(as.integer(task_id), as.integer(blocker_id)))
  invisible(TRUE)
}

# Read all dependency edges as a data.frame(task_id, blocker_id).
.board_deps <- function(db_path) {
  con <- .board_connect(db_path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  DBI::dbGetQuery(con, "SELECT task_id, blocker_id FROM deps")
}

# TRUE when the board is stalled: pending tasks remain, nobody is working on one
# (no 'claimed'), and none is currently claimable. Distinguishes a real
# dead-end from "just waiting for an in-progress blocker to finish" (in which
# case a worker should back off and retry, not exit).
.board_stalled <- function(db_path) {
  con <- .board_connect(db_path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  pending <- DBI::dbGetQuery(con,
    "SELECT COUNT(*) AS n FROM tasks WHERE status = 'pending'")$n[[1L]]
  if (pending == 0L) return(FALSE)
  inprog <- DBI::dbGetQuery(con,
    "SELECT COUNT(*) AS n FROM tasks WHERE status = 'claimed'")$n[[1L]]
  if (inprog > 0L) return(FALSE)   # someone is working -> a blocker may resolve
  tasks <- DBI::dbGetQuery(con, "SELECT id, owner, status FROM tasks")
  deps  <- DBI::dbGetQuery(con, "SELECT task_id, blocker_id FROM deps")
  length(.claimable_ids(tasks, deps)) == 0L
}

#' Reclaim tasks whose worker died mid-flight
#'
#' Resets `claimed` tasks that have been held longer than `timeout` seconds back
#' to `pending` (clearing owner + claimed_at) so another worker can pick them up.
#' This is the crash-recovery half of the coordinator: a worker that dies after
#' claiming a task would otherwise block its dependents forever. Called from the
#' worker loop's idle branch, so recovery happens without a separate lead.
#'
#' @param db_path Character. Board path.
#' @param timeout Numeric. Seconds a `claimed` task may be held before it is
#'   considered stale (default 300).
#' @return Integer. Number of tasks reclaimed.
#' @export
board_reclaim_stale <- function(db_path, timeout = 300) {
  con <- .board_connect(db_path)
  on.exit(DBI::dbDisconnect(con), add = TRUE)
  cutoff <- format(Sys.time() - timeout, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  DBI::dbExecute(con,
    "UPDATE tasks SET owner = NULL, status = 'pending', claimed_at = NULL
       WHERE status = 'claimed' AND claimed_at IS NOT NULL AND claimed_at < ?",
    params = list(cutoff))
}

#' Watch a task board for changes (event-driven coordinator engine)
#'
#' Wraps [watcher::watcher()] on the board file so a coordinator / live Shiny
#' view reacts to board changes the instant they land, instead of polling.
#' `callback` is invoked (with the changed paths) on every write to the board.
#' Returns the started watcher (call `$stop()` when done), or `NULL` when the
#' watcher package is unavailable -- callers then fall back to polling (mirrors
#' how Shiny uses watcher when present and polls otherwise).
#'
#' @param db_path Character. Board path.
#' @param callback Function of one argument (changed paths).
#' @param latency Numeric. Debounce seconds (default 0.3).
#' @return A started `watcher` R6 object, or `NULL` if watcher is unavailable.
#' @export
board_watch <- function(db_path, callback, latency = 0.3) {
  if (!requireNamespace("watcher", quietly = TRUE)) return(NULL)
  tryCatch({
    w <- watcher::watcher(path = db_path, callback = callback, latency = latency)
    w$start()
    w
  }, error = function(e) NULL)
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
                            blocked_by = NULL, worktree = FALSE, backoff = 0.5,
                            reclaim_timeout = 300,
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

  # Seed the board. Two passes so `blocked_by` can reference tasks by their
  # 1-based INDEX in `tasks` (the caller doesn't know DB ids yet): pass 1 adds
  # every task and records its id; pass 2 wires the DAG edges by index.
  board_create(db_path)
  ids <- integer(length(tasks))
  for (i in seq_along(tasks)) ids[i] <- board_add_task(db_path, tasks[[i]])
  if (!is.null(blocked_by)) {
    for (i in seq_along(tasks)) {
      for (j in as.integer(blocked_by[[i]] %||% integer(0))) {
        if (!is.na(j) && j >= 1L && j <= length(ids) && j != i)
          .board_add_dep(db_path, ids[i], ids[j])
      }
    }
    # Reject a cyclic dependency graph up front (it would deadlock the board).
    ok <- tryCatch({ .task_toposort(ids, .board_deps(db_path)); TRUE },
                   error = function(e) FALSE)
    if (!ok) cli::cli_abort("{.arg blocked_by} defines a cyclic task dependency graph.")
  }

  mirai::daemons(n_workers)
  on.exit(mirai::daemons(0L), add = TRUE)

  # Each worker loops: claim -> run -> complete, backing off while tasks remain
  # blocked by an in-progress task, until the board drains or stalls.
  worker_loop <- function(worker_id, db_path, model, base_url, api_key,
                          permission_mode, cwd, worktree, backoff,
                          reclaim_timeout) {
    Sys.setenv(CODEAGENT_BASE_URL = base_url, CODEAGENT_API_KEY = api_key,
               CODEAGENT_MODEL = model)
    # Team-level isolation: each worker gets its own git worktree so concurrent
    # edits never collide. Falls back to cwd if worktrees aren't available.
    wt <- if (isTRUE(worktree))
      tryCatch(codeagent:::.create_worktree(cwd), error = function(e) NULL) else NULL
    run_cwd <- if (is.null(wt)) cwd else wt
    on.exit(if (!is.null(wt))
      tryCatch(codeagent:::.cleanup_worktree(wt, cwd), error = function(e) NULL), add = TRUE)

    done <- 0L
    repeat {
      claimed <- tryCatch(codeagent::board_claim(db_path, worker_id),
                          error = function(e) NULL)
      if (is.null(claimed)) {
        # Nothing claimable: stop if the board is fully done or truly stalled;
        # otherwise a blocker is still in progress -- reclaim any task whose
        # worker died mid-flight (crash recovery), then wait and retry.
        if (codeagent:::.board_pending_count(db_path) == 0L) break
        codeagent::board_reclaim_stale(db_path, timeout = reclaim_timeout)
        if (codeagent:::.board_stalled(db_path)) break
        Sys.sleep(backoff)
        next
      }
      res <- tryCatch({
        client <- codeagent::codeagent_client(
          permission_mode = permission_mode, cwd = run_cwd, btw_groups = NULL)
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
  # Constant args must go through `.args` (mirai >= 2.x): passing them via `...`
  # does NOT bind them in the worker, so the loop would error out (swallowed) and
  # never claim a task, leaving the board untouched.
  m <- mirai::mirai_map(
    worker_ids, worker_loop,
    .args = list(db_path = db_path, model = model, base_url = base_url,
                 api_key = api_key, permission_mode = permission_mode,
                 cwd = cwd, worktree = isTRUE(worktree), backoff = backoff,
                 reclaim_timeout = reclaim_timeout))
  tryCatch(m[], error = function(e) NULL)   # wait for all workers

  board_status(db_path)
}
