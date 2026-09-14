#' @title Utility Functions
#' @description Internal helpers for codeagent. Adapted from ClaudeAgentSDK.
#' @name utils
#' @keywords internal
NULL

# ---------------------------------------------------------------------------
# Null-coalescing operator
# ---------------------------------------------------------------------------

#' @keywords internal
`%||%` <- function(a, b) if (!is.null(a)) a else b

# ---------------------------------------------------------------------------
# Path / hash helpers (for session management)
# ---------------------------------------------------------------------------

# Double-arithmetic hash to avoid 32-bit integer overflow (from ClaudeAgentSDK)
# Returns an 8-character lowercase hex string.
.simple_hash <- function(s) {
  chars <- utf8ToInt(s)
  h     <- 0
  for (ch in chars) {
    h <- ((h * 31) + ch) %% 4294967296
  }
  sprintf("%08x", h)
}

# Collapse path name to <= 200 chars + hash suffix
.sanitize_path <- function(name) {
  MAX_LEN <- 200L
  safe    <- gsub("[^a-zA-Z0-9_.-]", "_", name)
  if (nchar(safe) <= MAX_LEN) return(safe)
  suffix <- .simple_hash(name)
  paste0(substr(safe, 1L, MAX_LEN - nchar(suffix) - 1L), "_", suffix)
}

# Canonicalize a directory path (resolve symlinks, normalise)
.canonicalize_path <- function(d) {
  normalizePath(d, winslash = "/", mustWork = FALSE)
}

# Validate UUID v4 format
.validate_uuid <- function(s) {
  UUID_RE <- "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
  if (is.character(s) && length(s) == 1L && grepl(UUID_RE, s)) s else NULL
}

# Generate a UUID v4 string (RFC 4122)
.generate_uuid_v4 <- function() {
  hex <- paste(format(as.hexmode(sample(0:255, 16L, replace = TRUE)),
                      width = 2L), collapse = "")
  # Set version 4 in byte 7 (hex chars 13-14): high nibble = 0100
  hex <- paste0(substr(hex, 1L, 12L), "4", substr(hex, 14L, 16L),
                # Set RFC 4122 variant in byte 9 (hex char 17): bits 7-6 = 10
                # Correct: bitwAnd with 0x3 clears bits 3-2, then bitwOr sets bit 3
                format(as.hexmode(bitwOr(bitwAnd(strtoi(substr(hex, 17L, 17L), 16L),
                                                  0x3L), 0x8L)), width = 1L),
                substr(hex, 18L, 32L))
  paste0(substr(hex, 1L, 8L), "-", substr(hex, 9L, 12L), "-",
         substr(hex, 13L, 16L), "-", substr(hex, 17L, 20L), "-",
         substr(hex, 21L, 32L))
}

.restore_recovery_checked <- function(dest_path) {
  recovery <- paste0(dest_path, ".recovery.bak")
  committed <- paste0(recovery, ".committed")
  if (file.exists(recovery)) {
    if (file.exists(committed)) {
      if (unlink(recovery) != 0L)
        warning("Could not remove committed recovery copy: ", recovery,
                call. = FALSE)
    } else {
      if (!isTRUE(file.copy(recovery, dest_path, overwrite = TRUE)))
        stop("Could not restore interrupted replacement: ", dest_path,
             call. = FALSE)
      if (unlink(recovery) != 0L)
        warning("Restored replacement but could not remove recovery copy: ",
                recovery, call. = FALSE)
    }
  }
  if (file.exists(committed) && unlink(committed) != 0L)
    warning("Could not remove replacement commit marker: ", committed,
            call. = FALSE)
  invisible(dest_path)
}

.restore_directory_recoveries <- function(directory) {
  if (!dir.exists(directory)) return(invisible(directory))
  artifacts <- tryCatch(
    list.files(
      directory,
      pattern = "\\.recovery\\.bak(\\.committed)?$",
      full.names = TRUE),
    error = function(e) character())
  destinations <- unique(sub(
    "\\.recovery\\.bak(\\.committed)?$", "", artifacts))
  for (dest in destinations) .restore_recovery_checked(dest)
  invisible(directory)
}

# Replace a file with a prepared temporary file and verify every filesystem
# transition. The recovery path handles Windows, where rename does not replace
# an existing destination.
.replace_file_checked <- function(tmp_path, dest_path) {
  if (!file.exists(tmp_path))
    stop("Replacement source does not exist: ", tmp_path, call. = FALSE)

  .restore_recovery_checked(dest_path)

  if (isTRUE(suppressWarnings(file.rename(tmp_path, dest_path))))
    return(invisible(dest_path))

  if (!file.exists(dest_path))
    stop("Could not move temporary file into place: ", dest_path, call. = FALSE)

  recovery <- paste0(dest_path, ".recovery.bak")
  if (!isTRUE(file.copy(dest_path, recovery, overwrite = TRUE)))
    stop("Could not create replacement recovery copy: ", dest_path,
         call. = FALSE)
  committed <- paste0(recovery, ".committed")

  installed <- FALSE
  on.exit({
    if (!installed && file.exists(recovery)) {
      suppressWarnings(file.copy(recovery, dest_path, overwrite = TRUE))
      if (file.exists(committed)) unlink(committed)
    }
    if (file.exists(tmp_path)) unlink(tmp_path)
  }, add = TRUE)

  if (!isTRUE(file.copy(tmp_path, dest_path, overwrite = TRUE)))
    stop("Could not replace file: ", dest_path, call. = FALSE)
  hashes <- unname(tools::md5sum(c(tmp_path, dest_path)))
  if (length(hashes) != 2L || anyNA(hashes) || !identical(hashes[[1L]], hashes[[2L]]))
    stop("Replacement verification failed: ", dest_path, call. = FALSE)
  writeLines("committed", committed)

  installed <- TRUE
  unlink(tmp_path)
  if (file.exists(recovery) && unlink(recovery) != 0L)
    warning("Replaced file but could not remove recovery copy: ", recovery,
            call. = FALSE)
  if (file.exists(committed) && unlink(committed) != 0L)
    warning("Replaced file but could not remove commit marker: ", committed,
            call. = FALSE)
  invisible(dest_path)
}

# ---------------------------------------------------------------------------
# codeagent config directory helpers
# ---------------------------------------------------------------------------

.get_codeagent_dir <- function() {
  new_dir <- .new_codeagent_dir()
  old_dir <- .legacy_codeagent_dir()
  # One-time, lazy migration of a pre-rappdirs ~/.codeagent into the
  # OS-standard config dir. Guarded by an option so it is cheap on repeat calls.
  if (!isTRUE(getOption("codeagent._migrated"))) {
    tryCatch(.migrate_config_dir(old_dir, new_dir, quiet = TRUE),
             error = function(e) NULL)
    options(codeagent._migrated = TRUE)
  }
  # Safety fallback: if the new dir still does not exist but the legacy one does
  # (migration skipped/failed), keep using legacy so existing users never lose
  # their sessions/settings.
  if (!dir.exists(new_dir) && dir.exists(old_dir)) return(old_dir)
  new_dir
}

# Legacy (pre-rappdirs) location.
.legacy_codeagent_dir <- function() {
  file.path(path.expand("~"), ".codeagent")
}

# OS-standard config dir (rappdirs), with a CODEAGENT_HOME override and a
# graceful fallback to the legacy path when rappdirs is unavailable.
.new_codeagent_dir <- function() {
  ov <- Sys.getenv("CODEAGENT_HOME", "")
  if (nzchar(ov)) return(ov)
  if (!requireNamespace("rappdirs", quietly = TRUE)) return(.legacy_codeagent_dir())
  tryCatch(rappdirs::user_config_dir("codeagent"),
           error = function(e) .legacy_codeagent_dir())
}

# Copy a legacy config tree into the new dir. Idempotent: does nothing when the
# paths are identical, the legacy dir is absent, or the new dir already has
# content. Returns TRUE only when a migration actually happened.
.migrate_config_dir <- function(old_dir, new_dir, quiet = FALSE) {
  norm <- function(p) normalizePath(p, winslash = "/", mustWork = FALSE)
  if (identical(norm(old_dir), norm(new_dir))) return(invisible(FALSE))
  if (!dir.exists(old_dir)) return(invisible(FALSE))
  if (dir.exists(new_dir) &&
      length(list.files(new_dir, all.files = TRUE, no.. = TRUE)) > 0)
    return(invisible(FALSE))
  dir.create(new_dir, recursive = TRUE, showWarnings = FALSE)
  ok <- tryCatch({
    entries <- list.files(old_dir, full.names = TRUE, all.files = TRUE,
                          no.. = TRUE)
    if (length(entries))
      file.copy(entries, new_dir, recursive = TRUE, copy.date = TRUE)
    TRUE
  }, error = function(e) FALSE)
  if (isTRUE(all(ok)) && !quiet)
    message(sprintf("[codeagent] Migrated config: %s -> %s", old_dir, new_dir))
  invisible(isTRUE(all(ok)))
}

#' Migrate the codeagent config directory to the OS-standard location
#'
#' Copies a legacy `~/.codeagent` directory into the platform config directory
#' (`rappdirs::user_config_dir("codeagent")`). Idempotent and safe to call
#' repeatedly; normally runs automatically on first use.
#'
#' @param quiet Logical. Suppress the migration message.
#' @return Invisibly `TRUE` if a migration happened, else `FALSE`.
#' @export
migrate_config_dir <- function(quiet = FALSE) {
  .migrate_config_dir(.legacy_codeagent_dir(), .new_codeagent_dir(), quiet = quiet)
}

.get_sessions_dir <- function(cwd = NULL) {
  base_dir <- .get_codeagent_dir()
  if (!is.null(cwd)) {
    project_name <- .sanitize_path(.canonicalize_path(cwd))
    return(file.path(base_dir, "projects", project_name))
  }
  file.path(base_dir, "sessions")
}

# ---------------------------------------------------------------------------
# ellmer Chat helpers (reduce tryCatch boilerplate)
# ---------------------------------------------------------------------------

# Get turns from a chat object; return list() on error (e.g. ellmer API change)
.safe_get_turns <- function(chat, default = list()) {
  tryCatch(chat$get_turns(), error = function(e) default)
}

# Show a transient UI notice. Prefers bslib::show_toast when the installed
# bslib exports it (newer versions), else falls back to shiny::showNotification.
# Uses a dynamic lookup so R CMD check does not flag a hard dependency on an
# API that may be unexported in the installed bslib.
.ui_toast <- function(message, type = "message") {
  toast <- tryCatch(
    get("show_toast", envir = asNamespace("bslib"), inherits = FALSE),
    error = function(e) NULL
  )
  if (is.function(toast)) {
    ok <- tryCatch({ toast(message, type = type); TRUE }, error = function(e) FALSE)
    if (isTRUE(ok)) return(invisible(NULL))
  }
  sh_type <- switch(type, success = "message", error = "error",
                    warning = "warning", "message")
  tryCatch(shiny::showNotification(message, type = sh_type),
           error = function(e) NULL)
  invisible(NULL)
}

# Resolve a path to the object that permission checks and file operations use.
# Missing write targets are resolved through their nearest existing ancestor so
# symlinked/junction parents cannot move the effective target after lexical
# `..` cleanup.
.canonical_security_path <- function(path, root = getwd(),
                                     allow_missing = FALSE, .depth = 0L) {
  if (!is.character(path) || length(path) != 1L || is.na(path) ||
      !nzchar(path) || grepl("[\\x00]", path, perl = TRUE))
    stop("path must be a non-empty character(1)", call. = FALSE)

  root <- normalizePath(path.expand(root), winslash = "/", mustWork = TRUE)
  expanded <- path.expand(path)
  absolute <- grepl("^(?:[A-Za-z]:[/\\\\]|[/\\\\]{2}|/)", expanded,
                    perl = TRUE)
  candidate <- if (absolute) expanded else file.path(root, expanded)

  if (file.exists(candidate) || dir.exists(candidate))
    return(normalizePath(candidate, winslash = "/", mustWork = TRUE))
  if (!isTRUE(allow_missing))
    stop("File not found: ", path, call. = FALSE)
  if (.depth > 32L)
    stop("Too many symbolic-link resolutions for: ", path, call. = FALSE)

  suffix <- character()
  ancestor <- candidate
  while (!file.exists(ancestor) && !dir.exists(ancestor)) {
    link_target <- tryCatch(Sys.readlink(ancestor), error = function(e) "")
    if (length(link_target) == 1L && !is.na(link_target) &&
        nzchar(link_target)) {
      if (!grepl("^(?:[A-Za-z]:[/\\\\]|[/\\\\]{2}|/)", link_target,
                 perl = TRUE))
        link_target <- file.path(dirname(ancestor), link_target)
      target <- if (length(suffix))
        do.call(file.path, as.list(c(link_target, suffix))) else link_target
      return(.canonical_security_path(
        target, root, allow_missing = TRUE, .depth = .depth + 1L))
    }
    parent <- dirname(ancestor)
    leaf <- basename(ancestor)
    if (!nzchar(leaf) || leaf %in% c(".", "..") || identical(parent, ancestor))
      stop("Could not resolve a safe existing ancestor for: ", path,
           call. = FALSE)
    suffix <- c(leaf, suffix)
    ancestor <- parent
  }
  base <- normalizePath(ancestor, winslash = "/", mustWork = TRUE)
  resolved <- if (length(suffix))
    do.call(file.path, as.list(c(base, suffix))) else base
  normalizePath(resolved, winslash = "/", mustWork = FALSE)
}

.path_compare_key <- function(path) {
  key <- gsub("\\\\", "/", path)
  key <- sub("/+$", "", key)
  if (.Platform$OS.type == "windows") key <- tolower(key)
  key
}

.path_is_within <- function(path, root) {
  path <- .path_compare_key(path)
  root <- .path_compare_key(root)
  identical(path, root) || startsWith(path, paste0(root, "/"))
}

.canonicalize_path_pattern <- function(pattern, root = getwd()) {
  if (!is.character(pattern) || length(pattern) != 1L || !nzchar(pattern))
    return(pattern)
  wildcard <- regexpr("[*?\\[]", pattern, perl = TRUE)
  if (wildcard[[1L]] < 0L)
    return(.canonical_security_path(pattern, root, allow_missing = TRUE))

  prefix <- substr(pattern, 1L, wildcard[[1L]] - 1L)
  tail <- substr(pattern, wildcard[[1L]], nchar(pattern))
  base <- sub("[/\\\\]+$", "", prefix)
  if (!nzchar(base)) base <- "."
  paste0(.canonical_security_path(base, root, allow_missing = TRUE), "/", tail)
}

.canonicalize_permission_input <- function(tool_name, input, root = getwd()) {
  if (!is.list(input)) return(input)
  meta <- .tool_metadata(tool_name)
  keys <- meta$path_args %||% character()
  targets <- character()
  for (key in setdiff(keys, "patch")) {
    value <- input[[key]]
    if ((is.null(value) || !length(value)) &&
        tool_name %in% c("LS", "btw_tool_files_list"))
      value <- "."
    if (!is.character(value) || length(value) != 1L || !nzchar(value))
      stop("missing path argument for ", tool_name, call. = FALSE)
    input[[key]] <- .canonical_security_path(
      value, root, allow_missing = TRUE)
    targets <- c(targets, input[[key]])
  }
  if ("patch" %in% keys) {
    patch <- input[["patch"]]
    if (!is.character(patch) || length(patch) != 1L || !nzchar(patch))
      stop("missing patch argument for ", tool_name, call. = FALSE)
    if (!requireNamespace("btw", quietly = TRUE))
      stop("btw is required to validate a btw patch", call. = FALSE)
    ops <- tryCatch(
      utils::getFromNamespace("parse_patch", "btw")(patch),
      error = function(e) stop("invalid btw patch", call. = FALSE)
    )
    raw_paths <- unlist(lapply(ops, function(op)
      c(op$path %||% character(), op$move_to %||% character())),
      use.names = FALSE)
    raw_paths <- unique(raw_paths[nzchar(raw_paths)])
    if (!length(raw_paths))
      stop("patch contains no verifiable paths", call. = FALSE)
    targets <- c(targets, vapply(unique(raw_paths), function(path)
      .canonical_security_path(path, root, allow_missing = TRUE),
      character(1L)))
  }
  attr(input, "permission_targets") <- unique(targets)
  input
}

# Normalize a file path and check existence.
# Returns list(path = <path>) on success, list(error = <msg>) on failure.
.safe_normalize_path <- function(file_path, allow_missing = FALSE,
                                 root = getwd()) {
  tryCatch(
    list(path = .canonical_security_path(
      file_path, root = root, allow_missing = allow_missing)),
    error = function(e) list(error = paste0("[Error] ", conditionMessage(e)))
  )
}

# (r_mcp_server moved to mcp_client.R where MCP logic lives)
# ---------------------------------------------------------------------------
# Buffer / line splitting (streaming I/O)
# ---------------------------------------------------------------------------

#' Split buffered output into complete lines
#' @param buf Character(1). Current carry-over buffer.
#' @param new_output Character(1). New raw text to append.
#' @return Named list: `complete_lines` (character vector) and `remaining` (character(1)).
#' @keywords internal
split_lines_with_buffer <- function(buf, new_output) {
  combined <- paste0(buf, new_output)
  parts    <- strsplit(combined, "\n", fixed = TRUE)[[1]]
  if (length(parts) == 0L)
    return(list(complete_lines = character(0), remaining = ""))
  ends_with_newline <- substr(combined, nchar(combined), nchar(combined)) == "\n"
  if (ends_with_newline)
    return(list(complete_lines = parts, remaining = ""))
  list(complete_lines = parts[-length(parts)], remaining = parts[[length(parts)]])
}

# ---------------------------------------------------------------------------
# Semantic version comparison
# ---------------------------------------------------------------------------

.compare_versions <- function(a, b) {
  av <- as.integer(strsplit(a, "\\.")[[1]])
  bv <- as.integer(strsplit(b, "\\.")[[1]])
  for (i in seq_len(max(length(av), length(bv)))) {
    ai <- if (i <= length(av)) av[[i]] else 0L
    bi <- if (i <= length(bv)) bv[[i]] else 0L
    if (ai < bi) return(-1L)
    if (ai > bi) return(1L)
  }
  0L
}

# ---------------------------------------------------------------------------
# Token estimation (simple char/4 heuristic)
# ---------------------------------------------------------------------------

#' Estimate token count from text
#'
#' Uses a char/3.5 heuristic which gives better accuracy than char/4 for
#' mixed natural-language + code content. Rounding is conservative (ceiling).
#'
#' @param text Character vector or single string.
#' @return Integer. Estimated token count.
#' @keywords internal
estimate_tokens_text <- function(text) {
  as.integer(ceiling(nchar(paste(text, collapse = "")) / 3.5))
}

# ---------------------------------------------------------------------------
# Tool result truncation (3-layer resource management, Layer 1)
# ---------------------------------------------------------------------------

# Per-tool character limits (mirrors Claude Code's ContentBlockReplacementState)
.TOOL_MAX_CHARS <- list(
  Bash       = 30000L,
  Grep       = 20000L,
  FileEdit   = 100000L,
  Read       = 50000L,
  WebFetch   = 20000L,
  WebSearch  = 20000L,
  default    = 10000L
)

#' Truncate a tool result to the per-tool character limit
#'
#' Part of the three-layer resource management system.
#' Layer 1 limits single tool call output size.
#'
#' @param content Character(1). Tool output.
#' @param tool_name Character(1). Tool name for limit lookup.
#' @return Character(1). Possibly truncated content with a note appended.
#' @keywords internal
truncate_tool_result <- function(content, tool_name = "default") {
  limit <- .TOOL_MAX_CHARS[[tool_name]] %||% .TOOL_MAX_CHARS$default
  if (nchar(content) > limit) {
    paste0(substr(content, 1L, limit),
           "\n...[output truncated; ", nchar(content), " total chars]")
  } else {
    content
  }
}
