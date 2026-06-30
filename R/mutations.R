#' @title Session Mutation Functions
#' @description Rename, tag, and delete codeagent sessions stored under
#'   `~/.codeagent/projects/`. Appends typed metadata entries to JSONL files
#'   (append-only, most-recent-wins semantics). Adapted from ClaudeAgentSDK.
#' @name mutations
#' @keywords internal
NULL

# ---------------------------------------------------------------------------
# Session rewind: truncate in-memory conversation turns
# ---------------------------------------------------------------------------

#' Rewind a chat to an earlier point in the conversation
#'
#' Truncates the chat's in-memory turns to keep only the first `keep_turns`
#' user/assistant turns (ellmer counts each user and assistant message as a
#' separate turn, so a "round" is 2 turns).  This is a pure in-memory operation
#' via `Chat$set_turns()`; persist afterwards with [save_session()] to make the
#' rewind durable.
#'
#' @param chat An `ellmer::Chat` object (modified in place).
#' @param keep_turns Integer. Number of turns to keep from the start. If `NULL`
#'   or larger than the current turn count, nothing is truncated.
#' @return Invisibly the number of turns kept.
#' @export
truncate_chat_turns <- function(chat, keep_turns) {
  turns <- .safe_get_turns(chat)
  n     <- length(turns)
  if (n == 0L) return(invisible(0L))

  keep <- if (is.null(keep_turns)) n else as.integer(keep_turns)
  if (is.na(keep) || keep < 0L) keep <- 0L
  if (keep >= n) return(invisible(n))   # nothing to truncate

  kept <- if (keep == 0L) list() else turns[seq_len(keep)]
  tryCatch(chat$set_turns(kept), error = function(e) NULL)
  invisible(length(kept))
}

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

# Validate a session UUID and stop with an informative message if invalid.
.assert_valid_session_id <- function(session_id) {
  if (is.null(.validate_uuid(session_id)))
    stop("Invalid session_id: ", session_id, call. = FALSE)
  invisible(session_id)
}

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

#' Rename a session
#'
#' Appends a `custom-title` JSONL entry. Repeated calls are safe --
#' `list_sessions()` reads the last custom-title (most recent wins).
#'
#' @param session_id Character. UUID of the session.
#' @param title Character. New title (non-empty after trimming).
#' @param directory Character or NULL. Project working directory.
#' @return Invisibly NULL.
#' @export
rename_session <- function(session_id, title, directory = NULL) {
  .assert_valid_session_id(session_id)
  stripped <- trimws(title)
  if (!nzchar(stripped)) stop("title must be non-empty", call. = FALSE)

  data <- paste0(
    jsonlite::toJSON(
      list(type = "custom-title", customTitle = stripped, sessionId = session_id),
      auto_unbox = TRUE
    ), "\n"
  )
  .session_append(session_id, data, directory)
  invisible(NULL)
}

#' Tag a session
#'
#' Appends a `tag` JSONL entry. Pass `NULL` to clear the tag.
#'
#' @param session_id Character. UUID.
#' @param tag Character or NULL. Tag string (NULL clears).
#' @param directory Character or NULL. Project working directory.
#' @return Invisibly NULL.
#' @export
tag_session <- function(session_id, tag = NULL, directory = NULL) {
  .assert_valid_session_id(session_id)

  if (!is.null(tag)) {
    tag <- trimws(tag)
    if (!nzchar(tag)) stop("tag must be non-empty (use NULL to clear)", call. = FALSE)
    if (nchar(tag) > .MAX_SESSION_TAG_LEN)
      tag <- substr(tag, 1L, .MAX_SESSION_TAG_LEN)
  }

  data <- paste0(
    jsonlite::toJSON(
      list(type = "tag", tag = tag %||% "", sessionId = session_id),
      auto_unbox = TRUE
    ), "\n"
  )
  .session_append(session_id, data, directory)
  invisible(NULL)
}

#' Fork a session
#'
#' Creates an independent copy of an existing session JSONL file under a new
#' UUID.  A `session-fork` header entry is prepended to the copy so that the
#' origin can be traced.
#'
#' @param session_id Character. UUID of the session to fork.
#' @param directory Character or NULL. Project working directory used to
#'   locate the source file and write the fork.
#' @return Character(1). The new session UUID.
#' @export
fork_session <- function(session_id, directory = NULL) {
  .assert_valid_session_id(session_id)

  src_path <- .find_session_path(session_id, directory)
  if (is.null(src_path))
    stop("Session ", session_id, " not found.", call. = FALSE)

  new_id   <- .generate_uuid_v4()
  dest_dir <- dirname(src_path)
  dest_path <- file.path(dest_dir, paste0(new_id, ".jsonl"))

  # Read source lines and prepend a fork-provenance record
  src_lines <- tryCatch(readLines(src_path, warn = FALSE),
                         error = function(e)
                           stop("Cannot read source session: ", conditionMessage(e),
                                call. = FALSE))

  now <- paste0(format(Sys.time(), "%Y-%m-%dT%H:%M:%OS3", tz = "UTC"), "Z")
  fork_hdr <- jsonlite::toJSON(
    list(type = "session-fork", sessionId = new_id,
         sourceId = session_id, timestamp = now),
    auto_unbox = TRUE
  )

  tryCatch(
    writeLines(c(fork_hdr, src_lines), dest_path),
    error = function(e)
      stop("Failed to write forked session: ", conditionMessage(e), call. = FALSE)
  )

  new_id
}

#' Delete a session
#'
#' Permanently removes the session JSONL file.
#'
#' @param session_id Character. UUID.
#' @param directory Character or NULL. Project working directory.
#' @return Invisibly TRUE.
#' @export
delete_session <- function(session_id, directory = NULL) {
  .assert_valid_session_id(session_id)

  path <- .find_session_path(session_id, directory)
  if (is.null(path))
    stop("Session ", session_id, " not found.", call. = FALSE)

  if (!file.remove(path))
    stop("Failed to delete session file: ", path, call. = FALSE)

  invisible(TRUE)
}

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

.session_append <- function(session_id, data, directory) {
  path <- .find_session_path(session_id, directory)
  if (is.null(path))
    stop("Session ", session_id, " not found.", call. = FALSE)
  tryCatch(
    cat(data, file = path, append = TRUE),
    error = function(e)
      stop("Failed to append to session: ", conditionMessage(e), call. = FALSE)
  )
  invisible(NULL)
}
