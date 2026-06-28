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

# ---------------------------------------------------------------------------
# codeagent config directory helpers
# ---------------------------------------------------------------------------

.get_codeagent_dir <- function() {
  file.path(path.expand("~"), ".codeagent")
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

# Normalize a file path and check existence.
# Returns list(path = <path>) on success, list(error = <msg>) on failure.
.safe_normalize_path <- function(file_path) {
  path <- normalizePath(file_path, mustWork = FALSE)
  if (!file.exists(path))
    return(list(error = paste0("[Error] File not found: ", file_path)))
  list(path = path)
}

# ---------------------------------------------------------------------------
# MCP server helpers (mcptools integration) — preserved from ClaudeAgentSDK
# ---------------------------------------------------------------------------

#' Create an R-based MCP server entry
#'
#' Builds an `mcp_servers` list entry that launches an R subprocess running
#' `mcptools::mcp_server()` over stdio.
#'
#' @param tools_script Character(1) or NULL. Path to an `.R` script that yields
#'   a `list()` of `ellmer::tool()` objects.
#' @param session_tools Logical. Whether to expose built-in mcptools session
#'   management tools. Default `FALSE`.
#' @param rscript Character(1). Path to the `Rscript` binary.
#' @return A named list with `type`, `command`, and `args`.
#' @export
r_mcp_server <- function(
    tools_script  = NULL,
    session_tools = FALSE,
    rscript       = file.path(
      R.home("bin"),
      if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript"
    )) {
  if (!file.exists(rscript)) {
    fallback <- unname(Sys.which("Rscript"))
    if (!nzchar(fallback))
      stop("Cannot locate Rscript binary. Pass rscript= explicitly.", call. = FALSE)
    rscript <- fallback
  }
  st_str <- if (isTRUE(session_tools)) "TRUE" else "FALSE"
  rcode  <- if (is.null(tools_script)) {
    sprintf("mcptools::mcp_server(session_tools = %s)", st_str)
  } else {
    ts <- normalizePath(tools_script, mustWork = FALSE)
    ts <- gsub("'", "\\'", ts, fixed = TRUE)
    sprintf("mcptools::mcp_server(tools = '%s', session_tools = %s)", ts, st_str)
  }
  list(type = "stdio", command = rscript, args = c("-e", rcode))
}

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
