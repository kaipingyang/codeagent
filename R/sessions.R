#' @title Session Persistence
#' @description Save, list, and load codeagent sessions stored under
#'   `~/.codeagent/projects/`. Sessions are stored as JSONL files
#'   (one JSON object per conversation turn).
#' @name sessions
#' @keywords internal
NULL

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

.LITE_READ_BUF_SIZE   <- 65536L   # 64 KB head/tail for metadata extraction
.MAX_SESSION_TAG_LEN  <- 100L

# ---------------------------------------------------------------------------
# Session directory helpers
# ---------------------------------------------------------------------------

.get_project_session_dir <- function(cwd = NULL) {
  base <- .get_codeagent_dir()
  if (!is.null(cwd)) {
    project_key <- .sanitize_path(.canonicalize_path(cwd))
    return(file.path(base, "projects", project_key))
  }
  file.path(base, "projects")
}

.ensure_session_dir <- function(cwd = NULL) {
  d <- .get_project_session_dir(cwd)
  dir.create(d, showWarnings = FALSE, recursive = TRUE)
  d
}

# ---------------------------------------------------------------------------
# Save session
# ---------------------------------------------------------------------------

#' Save an ellmer Chat session to disk
#'
#' Serialises all turns in `chat` to a JSONL file under
#' `~/.codeagent/projects/<project_hash>/<session_id>.jsonl`.
#'
#' @param chat An `ellmer::Chat` object.
#' @param cwd Character. Working directory (used to key the project).
#' @param session_id Character or NULL. UUID; generated if NULL.
#' @param title Character or NULL. Optional human-readable title.
#' @return Character(1). The session UUID.
#' @export
save_session <- function(chat, cwd = getwd(),
                          session_id = NULL, title = NULL) {
  if (is.null(session_id)) session_id <- .generate_uuid_v4()
  session_dir <- .ensure_session_dir(cwd)
  file_path   <- file.path(session_dir, paste0(session_id, ".jsonl"))

  turns <- tryCatch(chat$get_turns(), error = function(e) list())
  now <- paste0(format(Sys.time(), "%Y-%m-%dT%H:%M:%OS3", tz = "UTC"), "Z")

  lines <- character(0)

  # Header line
  header <- list(
    type           = "session-start",
    sessionId      = session_id,
    cwd            = cwd,
    timestamp      = now,
    model          = tryCatch(chat$get_model() %||% "unknown", error = function(e) "unknown"),
    format_version = 1L
  )
  if (!is.null(title)) header$customTitle <- title
  lines <- c(lines, jsonlite::toJSON(header, auto_unbox = TRUE))

  # Turn lines
  for (turn in turns) {
    role     <- tryCatch(turn@role, error = function(e) "unknown")
    contents <- tryCatch(turn@contents, error = function(e) list())
    text_parts <- vapply(contents, function(c) {
      tryCatch(as.character(c@text %||% ""), error = function(e) "")
    }, character(1))
    text <- paste(text_parts[nzchar(text_parts)], collapse = "\n")

    entry <- list(
      type      = if (identical(role, "user")) "user" else "assistant",
      uuid      = .generate_uuid_v4(),
      sessionId = session_id,
      timestamp = now,
      message   = list(role = role, content = text)
    )
    lines <- c(lines, jsonlite::toJSON(entry, auto_unbox = TRUE))
  }

  writeLines(lines, file_path)
  session_id
}

# ---------------------------------------------------------------------------
# List sessions
# ---------------------------------------------------------------------------

#' List codeagent sessions
#'
#' Scans `~/.codeagent/projects/` for session files.
#'
#' @param directory Character or NULL. Project working directory.
#'   When `NULL`, all sessions across all projects are listed.
#' @param limit Integer or NULL. Max sessions to return.
#' @param offset Integer. Sessions to skip.
#' @return List of `SessionInfo` objects sorted by `last_modified` descending.
#' @export
list_sessions <- function(directory = NULL, limit = NULL, offset = 0L) {
  if (!is.null(directory)) {
    session_dir <- .get_project_session_dir(directory)
    sessions    <- .read_sessions_from_dir(session_dir)
  } else {
    projects_root <- file.path(.get_codeagent_dir(), "projects")
    dirs  <- tryCatch(list.dirs(projects_root, full.names = TRUE, recursive = FALSE),
                      error = function(e) character(0))
    sessions <- list()
    for (d in dirs) sessions <- c(sessions, .read_sessions_from_dir(d))
  }

  # Sort by last_modified descending
  if (length(sessions) > 0L) {
    mtimes   <- vapply(sessions, function(s) s$last_modified, numeric(1))
    sessions <- sessions[order(mtimes, decreasing = TRUE)]
  }

  # Pagination
  if (offset > 0L) {
    if (offset >= length(sessions)) return(list())
    sessions <- sessions[(offset + 1L):length(sessions)]
  }
  if (!is.null(limit) && limit > 0L)
    sessions <- sessions[seq_len(min(limit, length(sessions)))]

  sessions
}

# ---------------------------------------------------------------------------
# Get session info
# ---------------------------------------------------------------------------

#' Get metadata for a single session
#'
#' @param session_id Character. UUID.
#' @param directory Character or NULL. Project directory.
#' @return A `SessionInfo` object, or `NULL` if not found.
#' @export
get_session_info <- function(session_id, directory = NULL) {
  path <- .find_session_path(session_id, directory)
  if (is.null(path)) return(NULL)
  .read_session_info(session_id, path)
}

# ---------------------------------------------------------------------------
# Get session messages
# ---------------------------------------------------------------------------

#' Get messages from a session
#'
#' @param session_id Character. UUID.
#' @param directory Character or NULL. Project directory.
#' @param limit Integer or NULL. Max messages.
#' @param offset Integer. Messages to skip.
#' @return List of `SessionMessage` objects.
#' @export
get_session_messages <- function(session_id, directory = NULL,
                                  limit = NULL, offset = 0L) {
  path <- .find_session_path(session_id, directory)
  if (is.null(path)) return(list())

  lines <- tryCatch(readLines(path, warn = FALSE), error = function(e) character(0))
  messages <- list()

  for (ln in lines) {
    ln <- trimws(ln)
    if (!nzchar(ln)) next
    entry <- tryCatch(jsonlite::fromJSON(ln, simplifyVector = FALSE),
                      error = function(e) NULL)
    if (is.null(entry) || !is.list(entry)) next
    if (!(entry[["type"]] %in% c("user", "assistant"))) next

    msg  <- entry[["message"]] %||% list()
    text <- if (is.character(msg[["content"]])) msg[["content"]] else
            paste(unlist(lapply(msg[["content"]] %||% list(), function(b)
              b[["text"]] %||% "")), collapse = "\n")

    messages <- c(messages, list(SessionMessage(
      type       = entry[["type"]],
      text       = text,
      uuid       = entry[["uuid"]] %||% "",
      session_id = entry[["sessionId"]] %||% session_id
    )))
  }

  if (offset > 0L) {
    if (offset >= length(messages)) return(list())
    messages <- messages[(offset + 1L):length(messages)]
  }
  if (!is.null(limit) && limit > 0L)
    messages <- messages[seq_len(min(limit, length(messages)))]

  messages
}

# ---------------------------------------------------------------------------
# Restore a session's history into a Chat (harness, shared by CLI + Shiny)
# ---------------------------------------------------------------------------

#' Restore a saved session's messages into a Chat object
#'
#' Loads a session's messages and replays them as ellmer turns via
#' `chat$set_turns()`. Currently text-level (tool-call turns are flattened to
#' text); M7 will upgrade this to lossless `contents_record/replay`.
#'
#' @param chat An `ellmer::Chat` to populate.
#' @param session_id Character. Session UUID. If `NULL`, the most recent
#'   session under `cwd` is used (for `--continue`).
#' @param cwd Character. Project directory for session lookup.
#' @return Invisibly, the resolved session id (or `NULL` if none found).
#' @export
restore_session_into_chat <- function(chat, session_id = NULL, cwd = getwd()) {
  if (is.null(session_id)) {
    sl <- tryCatch(list_sessions(cwd, limit = 1L), error = function(e) list())
    if (length(sl) == 0L) return(invisible(NULL))
    session_id <- sl[[1L]]$session_id
  }
  msgs <- tryCatch(get_session_messages(session_id, cwd), error = function(e) list())
  if (length(msgs) == 0L) return(invisible(NULL))

  turns <- lapply(msgs, function(m) {
    tryCatch(ellmer::Turn(m$type, list(ellmer::ContentText(m$text))),
             error = function(e) NULL)
  })
  turns <- Filter(Negate(is.null), turns)
  tryCatch(chat$set_turns(turns), error = function(e) NULL)
  invisible(session_id)
}


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

.find_session_path <- function(session_id, directory) {
  fname <- paste0(session_id, ".jsonl")
  if (!is.null(directory)) {
    path <- file.path(.get_project_session_dir(directory), fname)
    if (file.exists(path)) return(path)
    return(NULL)
  }
  # Search all projects
  root <- file.path(.get_codeagent_dir(), "projects")
  dirs <- tryCatch(list.dirs(root, full.names = TRUE, recursive = FALSE),
                   error = function(e) character(0))
  for (d in dirs) {
    p <- file.path(d, fname)
    if (file.exists(p)) return(p)
  }
  NULL
}

.read_sessions_from_dir <- function(session_dir) {
  files <- tryCatch(
    list.files(session_dir, pattern = "\\.jsonl$", full.names = TRUE),
    error = function(e) character(0)
  )
  results <- list()
  for (f in files) {
    stem <- tools::file_path_sans_ext(basename(f))
    if (!grepl("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$",
               stem, ignore.case = TRUE, perl = TRUE)) next
    info <- .read_session_info(stem, f)
    if (!is.null(info)) results <- c(results, list(info))
  }
  results
}

# ---------------------------------------------------------------------------
# Session migration
# ---------------------------------------------------------------------------

#' Migrate legacy session files to the current format version
#'
#' Scans all session JSONL files and adds `format_version` to headers that are
#' missing it.  Safe to run multiple times (already-migrated files are skipped).
#'
#' @param directory Character or NULL. Project working directory; `NULL` scans
#'   all projects under `~/.codeagent/projects/`.
#' @return Invisibly returns the number of files updated.
#' @export
migrate_sessions <- function(directory = NULL) {
  if (!is.null(directory)) {
    dirs <- .get_project_session_dir(directory)
  } else {
    root <- file.path(.get_codeagent_dir(), "projects")
    dirs <- tryCatch(list.dirs(root, full.names = TRUE, recursive = FALSE),
                     error = function(e) character(0))
  }

  updated <- 0L
  for (d in dirs) {
    if (!dir.exists(d)) next
    files <- list.files(d, pattern = "\\.jsonl$", full.names = TRUE)
    for (f in files) {
      lines <- tryCatch(readLines(f, warn = FALSE), error = function(e) NULL)
      if (is.null(lines) || length(lines) == 0L) next

      hdr <- tryCatch(jsonlite::fromJSON(lines[[1L]], simplifyVector = FALSE),
                      error = function(e) NULL)
      if (is.null(hdr) || !identical(hdr[["type"]], "session-start")) next
      if (!is.null(hdr[["format_version"]])) next  # already current

      hdr[["format_version"]] <- 1L
      lines[[1L]] <- jsonlite::toJSON(hdr, auto_unbox = TRUE)
      tryCatch(writeLines(lines, f), error = function(e) NULL)
      updated <- updated + 1L
    }
  }

  invisible(updated)
}

.read_session_info <- function(session_id, path) {
  if (!file.exists(path)) return(NULL)
  fi    <- file.info(path)
  mtime <- as.numeric(fi$mtime) * 1000

  # Read all lines: first line is the header; later lines may contain
  # appended mutations (custom-title, tag) — scan from the end for the
  # most-recent custom-title entry (most-recent-wins semantics).
  all_lines <- tryCatch(readLines(path, warn = FALSE), error = function(e) character(0))
  if (length(all_lines) == 0L) return(NULL)

  entry <- tryCatch(jsonlite::fromJSON(all_lines[[1L]], simplifyVector = FALSE),
                    error = function(e) list())

  # Walk lines in reverse to find the most recent custom-title mutation
  appended_title <- NULL
  if (length(all_lines) > 1L) {
    for (ln in rev(all_lines[-1L])) {
      obj <- tryCatch(jsonlite::fromJSON(ln, simplifyVector = FALSE),
                      error = function(e) NULL)
      if (!is.null(obj) && identical(obj[["type"]], "custom-title")) {
        appended_title <- obj[["customTitle"]]
        break
      }
    }
  }

  custom_title <- appended_title %||% entry[["customTitle"]] %||% NULL

  # If no custom title, use the first user message as a readable label
  first_user_msg <- NULL
  if (is.null(custom_title) && length(all_lines) > 1L) {
    for (ln in all_lines[-1L]) {
      obj <- tryCatch(jsonlite::fromJSON(ln, simplifyVector = FALSE),
                      error = function(e) NULL)
      if (!is.null(obj) && identical(obj[["type"]], "user")) {
        msg <- obj[["message"]] %||% list()
        txt <- if (is.character(msg[["content"]])) msg[["content"]] else ""
        if (nzchar(txt)) {
          first_user_msg <- substr(txt, 1L, 50L)
          if (nchar(txt) > 50L) first_user_msg <- paste0(first_user_msg, "...")
          break
        }
      }
    }
  }

  title <- custom_title %||% first_user_msg %||% format(
    as.POSIXct(mtime / 1000, origin = "1970-01-01"), "%Y-%m-%d %H:%M"
  )
  cwd          <- entry[["cwd"]] %||% NULL

  SessionInfo(
    session_id    = session_id,
    summary       = title,
    last_modified = mtime,
    file_size     = fi$size,
    custom_title  = custom_title,
    cwd           = cwd
  )
}
