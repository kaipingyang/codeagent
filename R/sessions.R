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
#' Appends the conversation to a JSONL log under
#' `<CODEAGENT_HOME>/projects/<project>/<session_id>.jsonl` (format version 2).
#' Each new turn is one `user` / `assistant` entry holding its display text and
#' its lossless record; entries are chained by `uuid` / `parentUuid`. Turns
#' already in the file are not written again. When the chat's context is no
#' longer "the saved turns plus new ones" -- compaction, rewind, clear -- a
#' `system` / `compact_boundary` entry is appended with a snapshot of the new
#' context (`parentUuid: null`, `logicalParentUuid` pointing at the last entry
#' before it), so earlier turns stay in the file. The model context restores
#' from the last boundary on ([restore_session_into_chat()]); the display keeps
#' every turn. A version 1 file (rewritten whole on every save) is migrated on
#' its first save.
#'
#' @param chat An `ellmer::Chat` object.
#' @param cwd Character. Working directory (used to key the project).
#' @param session_id Character or NULL. UUID; generated if NULL.
#' @param title Character or NULL. Optional human-readable title.
#' @param assistant_text_override Character or NULL. Safe finalized text for the
#'   last assistant turn's presentation line. The lossless record keeps the
#'   provider-facing turn.
#' @param genui_state List or NULL. The generative UI canvas state to persist
#'   with the conversation; appended when it differs from the last saved one.
#' @param context_event Character or NULL. What changed the context when it is
#'   not a continuation (`"compact"`, `"rewind"`, `"clear"`); inferred when NULL.
#' @return Character(1). The session UUID.
#' @export
save_session <- function(chat, cwd = getwd(),
                          session_id = NULL, title = NULL,
                          assistant_text_override = NULL,
                          genui_state = NULL, context_event = NULL) {
  if (is.null(session_id)) session_id <- .generate_uuid_v4()
  session_dir <- .ensure_session_dir(cwd)
  file_path   <- file.path(session_dir, paste0(session_id, ".jsonl"))

  turns <- tryCatch(chat$get_turns(), error = function(e) list())
  # Drop empty assistant turns (no text, no tool request/result, no thinking --
  # e.g. a failed/interrupted stream). Persisting them makes a restored session
  # show a perpetual "..." typing bubble, and sends useless empties to the LLM
  # on continuation.
  turns <- Filter(function(t) !.turn_is_empty(t), turns)
  now <- .session_now()

  log <- .session_log_read(file_path)
  if (!is.null(log) && log$version < 2L) {
    .session_log_migrate(file_path, log, session_id)
    log <- .session_log_read(file_path)
  }

  lines <- character(0)
  parent <- if (is.null(log)) NULL else log$last_uuid
  add_line <- function(entry) {
    lines <<- c(lines, as.character(jsonlite::toJSON(entry, auto_unbox = TRUE, null = "null")))
    if (!is.null(entry$uuid)) parent <<- entry$uuid
  }

  if (is.null(log)) {
    header <- list(
      type           = "session-start",
      sessionId      = session_id,
      cwd            = cwd,
      timestamp      = now,
      model          = tryCatch(chat$get_model() %||% "unknown", error = function(e) "unknown"),
      format_version = .SESSION_FORMAT_VERSION
    )
    if (!is.null(title)) header$customTitle <- title
    add_line(header)
  } else if (!is.null(title) && !identical(title, log$title)) {
    add_line(list(type = "custom-title", customTitle = title, sessionId = session_id))
  }

  records <- lapply(turns, function(t) tryCatch(ellmer::contents_record(t), error = function(e) NULL))
  digests <- vapply(records, .session_digest, character(1))
  ctx <- if (is.null(log)) character(0) else log$context_digests
  continuation <- length(ctx) <= length(digests) &&
    identical(ctx, digests[seq_along(ctx)])

  if (continuation) {
    add <- setdiff(seq_along(turns), seq_along(ctx))
  } else {
    # Longest common prefix of the saved context and the chat's turns.
    n <- min(length(ctx), length(digests))
    common <- if (n) { d <- which(ctx[seq_len(n)] != digests[seq_len(n)]); if (length(d)) d[1] - 1L else n } else 0L
    is_summary <- vapply(turns, .is_compaction_summary_turn, logical(1))
    trigger <- context_event %||% if (!length(digests)) "clear"
      else if (any(is_summary)) "compact"
      else if (common == length(digests) || common > 0L) "rewind"
      else "compact"
    # The new context: what precedes the turns this save adds. Turns the display
    # has not shown -- a reply that arrived in the same save as the compaction,
    # or the turns after a rewind -- follow the boundary as ordinary entries.
    # The compaction summary itself is context, not conversation.
    shown <- if (is.null(log)) character(0) else log$shown_digests
    add <- if (identical(trigger, "rewind")) setdiff(seq_along(turns), seq_len(common))
           else which(!(digests %in% shown) & !is_summary)
    tail_ok <- !length(add) || identical(add, seq.int(length(turns) - length(add) + 1L, length(turns)))
    if (!tail_ok) add <- integer(0)          # cannot split the context: snapshot it whole
    base <- setdiff(seq_along(turns), add)
    removed <- if (trigger %in% c("rewind", "clear")) setdiff(ctx, digests[base]) else character(0)
    add_line(list(
      type              = "system",
      subtype           = "compact_boundary",
      content           = "Conversation compacted",
      uuid              = .generate_uuid_v4(),
      parentUuid        = NULL,
      logicalParentUuid = parent,
      sessionId         = session_id,
      timestamp         = now,
      compactMetadata   = list(
        trigger        = trigger,
        preTurns       = length(ctx),
        postTurns      = length(digests),
        removedDigests = I(removed)),
      contextDigests    = I(digests[base]),
      state             = .session_records_encode(records[base])
    ))
  }

  roles <- vapply(turns, function(turn)
    tryCatch(turn@role, error = function(e) "unknown"), character(1L))
  assistant_idx <- which(roles == "assistant")
  last_assistant <- if (length(assistant_idx)) utils::tail(assistant_idx, 1L) else NA_integer_
  for (i in add) {
    text <- .session_turn_text(turns[[i]])
    if (!is.null(assistant_text_override) && identical(i, last_assistant))
      text <- as.character(assistant_text_override)[1L]
    add_line(list(
      type       = if (identical(roles[[i]], "user")) "user" else "assistant",
      uuid       = .generate_uuid_v4(),
      parentUuid = parent,
      sessionId  = session_id,
      timestamp  = now,
      message    = list(role = roles[[i]], content = text),
      digest     = digests[[i]],
      state      = .session_records_encode(records[i])
    ))
  }

  # Canvas state: appended when it changed (readers take the last one).
  if (!is.null(genui_state)) {
    gd <- .session_digest(genui_state)
    if (!identical(gd, if (is.null(log)) NULL else log$genui_digest))
      lines <- c(lines, as.character(jsonlite::toJSON(
        list(type = "genui-state", sessionId = session_id, timestamp = now,
             digest = gd, state = genui_state),
        auto_unbox = TRUE, null = "null")))
  }

  if (length(lines)) {
    if (is.null(log)) .session_write_new(file_path, lines)
    else .session_append_lines(file_path, lines)
  }
  session_id
}

#' Record a context change in a saved session
#'
#' Appends a `compact_boundary` to the session's log when the chat's context
#' is no longer a continuation of what was saved (compaction, rewind, clear).
#' Called where the context changes -- before a turn, after `/compact`,
#' `/clear`, `/rewind` -- so the end-of-turn save only appends the new turns.
#' A session that has no file yet is left alone.
#' @param chat An `ellmer::Chat` object.
#' @param cwd Character. Project directory.
#' @param session_id Character or NULL. Session UUID.
#' @param context_event Character or NULL. See [save_session()].
#' @return Invisibly TRUE when the session file exists.
#' @keywords internal
.session_sync_context <- function(chat, cwd, session_id, context_event = NULL) {
  if (is.null(session_id) || is.null(.validate_uuid(session_id))) return(invisible(FALSE))
  path <- file.path(.get_project_session_dir(cwd), paste0(session_id, ".jsonl"))
  if (!file.exists(path)) return(invisible(FALSE))
  tryCatch(save_session(chat, cwd, session_id, context_event = context_event),
           error = function(e) NULL)
  invisible(TRUE)
}

.SESSION_FORMAT_VERSION <- 2L

.session_now <- function()
  paste0(format(Sys.time(), "%Y-%m-%dT%H:%M:%OS3", tz = "UTC"), "Z")

.session_digest <- function(x) {
  f <- tempfile(fileext = ".rds")
  on.exit(unlink(f), add = TRUE)
  saveRDS(x, f, version = 2L, compress = FALSE)
  unname(tools::md5sum(f))
}

.session_turn_text <- function(turn) {
  contents <- tryCatch(turn@contents, error = function(e) list())
  parts <- vapply(contents, function(c)
    tryCatch(as.character(c@text %||% ""), error = function(e) ""), character(1))
  paste(parts[nzchar(parts)], collapse = "\n")
}

# The summary turn a compaction puts at the head of the context.
.is_compaction_summary_turn <- function(turn) {
  if (!identical(tryCatch(turn@role, error = function(e) ""), "user")) return(FALSE)
  txt <- .session_turn_text(turn)
  grepl("^(Summary:\\n|\\[Session Memory Summary\\]\\n)", txt)
}

.session_records_encode <- function(records) {
  json <- jsonlite::serializeJSON(records)
  base64enc::base64encode(memCompress(charToRaw(json), "gzip"))
}

.session_records_decode <- function(state_str, tools = list()) {
  raw  <- base64enc::base64decode(state_str)
  json <- rawToChar(memDecompress(raw, "gzip"))
  recorded <- jsonlite::unserializeJSON(json)
  lapply(recorded, ellmer::contents_replay, tools = tools)
}

# Append whole lines. A previous write cut short leaves the file without a
# final newline: start on a fresh line so the new entries stay parseable.
.session_append_lines <- function(file_path, lines) {
  size <- file.size(file_path)
  lead <- ""
  if (isTRUE(size > 0)) {
    con <- file(file_path, "rb"); on.exit(close(con), add = TRUE)
    seek(con, size - 1L)
    if (!identical(readBin(con, "raw", 1L), charToRaw("\n"))) lead <- "\n"
  }
  cat(lead, paste0(lines, "\n"), sep = "", file = file_path, append = TRUE)
}

.session_write_new <- function(file_path, lines) {
  tmp_file <- tempfile(pattern = "session_", tmpdir = dirname(file_path), fileext = ".jsonl")
  on.exit(if (file.exists(tmp_file)) unlink(tmp_file), add = TRUE)
  writeLines(lines, tmp_file)
  .replace_file_checked(tmp_file, file_path)
}

# Parse a session file. NULL when it does not exist. Lines that do not parse
# (a write cut short) are skipped.
.session_log_read <- function(path) {
  if (!file.exists(path)) return(NULL)
  lines <- tryCatch(readLines(path, warn = FALSE), error = function(e) character(0))
  entries <- list()
  for (ln in lines) {
    if (!nzchar(trimws(ln))) next
    e <- tryCatch(jsonlite::fromJSON(ln, simplifyVector = FALSE), error = function(e) NULL)
    if (is.list(e) && !is.null(e[["type"]])) entries[[length(entries) + 1L]] <- e
  }
  header <- Filter(function(e) identical(e$type, "session-start"), entries)
  version <- if (length(header)) as.integer(header[[1]]$format_version %||% 1L) else 1L
  ctx <- character(0); shown <- character(0); title <- NULL; genui <- NULL; last_uuid <- NULL
  for (e in entries) {
    if (!is.null(e$uuid)) last_uuid <- e$uuid
    if (identical(e$type, "session-start") && !is.null(e$customTitle)) title <- e$customTitle
    else if (identical(e$type, "custom-title")) title <- e$customTitle
    else if (identical(e$type, "genui-state")) genui <- e$digest %||% .session_digest(e$state)
    else if (identical(e$subtype, "compact_boundary")) {
      ctx <- as.character(unlist(e$contextDigests))
      for (d in as.character(unlist(e$compactMetadata$removedDigests))) {
        hit <- which(shown == d)
        if (length(hit)) shown <- shown[-utils::tail(hit, 1L)]
      }
    } else if (e$type %in% c("user", "assistant") && !is.null(e$digest)) {
      ctx <- c(ctx, e$digest); shown <- c(shown, e$digest)
    }
  }
  list(version = version, entries = entries, context_digests = ctx, shown_digests = shown,
       title = title, genui_digest = genui, last_uuid = last_uuid)
}

# Rewrite a version 1 file (one chat-state line + text lines) as version 2:
# header, one entry per turn, then the other lines (titles, tags, canvas).
.session_log_migrate <- function(path, log, session_id) {
  turns <- tryCatch(.session_v1_state(log$entries), error = function(e) NULL)
  text_lines <- Filter(function(e) e$type %in% c("user", "assistant"), log$entries)
  if (is.null(turns)) turns <- lapply(text_lines, function(e)
    ellmer::Turn(e$type, list(ellmer::ContentText(as.character(e$message$content %||% "")))))
  header <- Filter(function(e) identical(e$type, "session-start"), log$entries)
  header <- if (length(header)) header[[1]] else
    list(type = "session-start", sessionId = session_id, timestamp = .session_now())
  header$format_version <- .SESSION_FORMAT_VERSION
  out <- as.character(jsonlite::toJSON(header, auto_unbox = TRUE, null = "null"))
  parent <- NULL
  same <- length(text_lines) == length(turns)
  for (i in seq_along(turns)) {
    rec <- ellmer::contents_record(turns[[i]])
    role <- tryCatch(turns[[i]]@role, error = function(e) "user")
    uuid <- .generate_uuid_v4()
    out <- c(out, as.character(jsonlite::toJSON(list(
      type = if (identical(role, "user")) "user" else "assistant", uuid = uuid, parentUuid = parent,
      sessionId = session_id, timestamp = header$timestamp %||% .session_now(),
      message = list(role = role, content = if (same) as.character(text_lines[[i]]$message$content %||% "")
                                             else .session_turn_text(turns[[i]])),
      digest = .session_digest(rec), state = .session_records_encode(list(rec))),
      auto_unbox = TRUE, null = "null")))
    parent <- uuid
  }
  keep <- Filter(function(e) !e$type %in% c("session-start", "chat-state", "user", "assistant"), log$entries)
  for (e in keep) out <- c(out, as.character(jsonlite::toJSON(e, auto_unbox = TRUE, null = "null")))
  .session_write_new(path, out)
}

.session_v1_state <- function(entries, tools = list()) {
  st <- Filter(function(e) identical(e$type, "chat-state"), entries)
  if (!length(st)) return(NULL)
  .session_state_decode(st[[length(st)]]$state, tools = tools)
}

#' Turns of a saved session as the user saw them
#'
#' Every turn of the log in order, without the turns a rewind or clear
#' removed; compaction does not remove anything. For a version 1 file, its
#' saved turns.
#' @param session_id Character. Session UUID.
#' @param cwd Character. Project directory.
#' @param tools List of `ellmer::tool()` objects to rebind on replay.
#' @return `list(turns, boundaries)`: ellmer turns, and for each compaction the
#'   number of turns shown before it. `NULL` when the session is not found.
#' @keywords internal
.read_session_display_turns <- function(session_id, cwd = getwd(), tools = list()) {
  path <- .find_session_path(session_id, cwd)
  if (is.null(path)) return(NULL)
  log <- .session_log_read(path)
  if (log$version < 2L) {
    turns <- .session_v1_state(log$entries, tools) %||% list()
    return(list(turns = turns, boundaries = integer(0)))
  }
  shown <- list(); dig <- character(0); boundaries <- integer(0)
  for (e in log$entries) {
    if (identical(e$subtype, "compact_boundary")) {
      removed <- as.character(unlist(e$compactMetadata$removedDigests))
      for (d in removed) {
        hit <- which(dig == d)
        if (length(hit)) { k <- utils::tail(hit, 1L); shown <- shown[-k]; dig <- dig[-k] }
      }
      if (identical(e$compactMetadata$trigger, "compact") && length(shown))
        boundaries <- c(boundaries, length(shown))
    } else if (e$type %in% c("user", "assistant") && !is.null(e$state)) {
      t <- tryCatch(.session_records_decode(e$state, tools)[[1]], error = function(err) NULL)
      if (!is.null(t)) { shown[[length(shown) + 1L]] <- t; dig <- c(dig, e$digest %||% "") }
    }
  }
  list(turns = shown, boundaries = unique(boundaries))
}


# ---------------------------------------------------------------------------
# Lossless chat-state codec (contents_record + gzip + base64)
# Mirrors shinychat's client_state pattern: serializeJSON is lossless where
# toJSON is not, so tool requests/results survive a round trip.
# ---------------------------------------------------------------------------

.session_state_encode <- function(chat, turns = NULL) {
  if (is.null(turns)) turns <- chat$get_turns()
  recorded <- lapply(turns, ellmer::contents_record)
  json     <- jsonlite::serializeJSON(recorded)
  base64enc::base64encode(memCompress(charToRaw(json), "gzip"))
}

# An assistant turn is "empty" when it has nothing renderable: no visible text
# and no non-text content (tool request/result, thinking, image). Such turns
# come from a failed/interrupted stream and, if persisted, render as a stuck
# "..." bubble on restore. User turns are never treated as empty here.
.turn_is_empty <- function(turn) {
  role <- tryCatch(turn@role, error = function(e) "")
  if (!identical(role, "assistant")) return(FALSE)
  contents <- tryCatch(turn@contents, error = function(e) list())
  if (!length(contents)) return(TRUE)
  any_renderable <- any(vapply(contents, function(cc) {
    if (!inherits(cc, "ellmer::ContentText")) return(TRUE)  # tool/thinking/etc.
    txt <- tryCatch(cc@text, error = function(e) "")
    nzchar(trimws(paste(txt %||% "", collapse = "")))
  }, logical(1)))
  !any_renderable
}

.session_state_decode <- function(state_str, tools = list()) {
  raw  <- base64enc::base64decode(state_str)
  json <- rawToChar(memDecompress(raw, "gzip"))
  recorded <- jsonlite::unserializeJSON(json)
  lapply(recorded, ellmer::contents_replay, tools = tools)
}

#' Read a session's lossless model context (if present)
#'
#' Version 2: the snapshot of the last `compact_boundary` plus every turn
#' saved after it (the model sees only what follows the last boundary).
#' Version 1: its `chat-state` line. `NULL` for text-only legacy sessions so
#' callers can fall back to text restoration.
#'
#' @param session_id Character. Session UUID.
#' @param cwd Character. Project directory.
#' @param tools List of `ellmer::tool()` objects to rebind on replay.
#' @return List of ellmer turns, or `NULL`.
#' @keywords internal
.read_session_state <- function(session_id, cwd = getwd(), tools = list()) {
  path <- .find_session_path(session_id, cwd)
  if (is.null(path)) return(NULL)
  log <- .session_log_read(path)
  if (log$version < 2L)
    return(tryCatch(.session_v1_state(log$entries, tools), error = function(e) NULL))
  turns <- list()
  for (e in log$entries) {
    if (identical(e$subtype, "compact_boundary")) {
      turns <- tryCatch(.session_records_decode(e$state, tools), error = function(err) list())
    } else if (e$type %in% c("user", "assistant") && !is.null(e$state)) {
      t <- tryCatch(.session_records_decode(e$state, tools), error = function(err) list())
      turns <- c(turns, t)
    }
  }
  turns
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
#' Loads a session and replays it into a Chat. Prefers the lossless
#' `chat-state` record (tool calls/results intact, via
#' `contents_record()`/`contents_replay()`); falls back to text-level turns for
#' pre-lossless sessions.
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

  # Prefer lossless chat-state (preserves tool calls); fall back to text turns.
  tools <- tryCatch(chat$get_tools(), error = function(e) list())
  state_turns <- tryCatch(.read_session_state(session_id, cwd, tools = tools),
                          error = function(e) NULL)
  if (!is.null(state_turns) && length(state_turns) > 0L) {
    tryCatch(chat$set_turns(state_turns), error = function(e) NULL)
    return(invisible(session_id))
  }

  # Legacy fallback: text-only restoration.
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
    session_dir <- .get_project_session_dir(directory)
    .restore_directory_recoveries(session_dir)
    path <- file.path(session_dir, fname)
    if (file.exists(path)) return(path)
    return(NULL)
  }
  # Search all projects
  root <- file.path(.get_codeagent_dir(), "projects")
  dirs <- tryCatch(list.dirs(root, full.names = TRUE, recursive = FALSE),
                   error = function(e) character(0))
  for (d in dirs) {
    .restore_directory_recoveries(d)
    p <- file.path(d, fname)
    if (file.exists(p)) return(p)
  }
  NULL
}

.read_sessions_from_dir <- function(session_dir) {
  .restore_directory_recoveries(session_dir)
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
  # appended mutations (custom-title, tag) -- scan from the end for the
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
        txt <- .strip_system_reminder(txt)   # ephemeral context, not a title
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
