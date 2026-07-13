#' @title CLI dispatch helpers
#' @description
#'   Pure functions for resolving permission mode and dispatching CLI arguments.
#'   Kept separate from exec/codeagent.R so they can be unit-tested without
#'   running the full CLI entry point.
#' @name cli_dispatch
#' @keywords internal
NULL

#' Resolve permission mode from the yolo flag.
#' @param yolo Logical. When TRUE returns "bypass", otherwise "default".
#' @return Character scalar: "bypass" or "default".
#' @keywords internal
.ca_resolve_mode <- function(yolo = FALSE) {
  if (isTRUE(yolo)) "bypass" else "default"
}

#' Dispatch CLI arguments to a command + rest vector.
#'
#' @param argv Character vector of positional arguments (no flags).
#' @param print_mode Logical. TRUE when `-p`/`--print` was passed.
#' @return Named list: `cmd` (character), `rest` (character vector).
#' @keywords internal
.ca_dispatch <- function(argv = character(), print_mode = FALSE) {
  known <- c("run", "chat", "repl", "app", "sessions", "skills", "mcp", "info")
  argv  <- as.character(argv %||% character())
  if (length(argv) && argv[[1L]] %in% known)
    return(list(cmd = argv[[1L]], rest = argv[-1L]))
  if (isTRUE(print_mode) || length(argv) > 0L)
    return(list(cmd = "run", rest = argv))
  list(cmd = "chat", rest = character())
}

#' Format and print agent output.
#'
#' @param x Character scalar (agent response).
#' @param output_fmt Character. "text" (default) or "json".
#' @param session_id Character or NULL. Included in JSON output.
#' @keywords internal
.ca_format_output <- function(x, output_fmt = "text", session_id = NULL) {
  if (identical(output_fmt, "json")) {
    cat(jsonlite::toJSON(
      list(response   = if (is.character(x)) x else format(x),
           session_id = session_id %||% NA_character_),
      auto_unbox = TRUE), "\n")
  } else {
    if (is.character(x)) cat(paste(x, collapse = "\n"), "\n")
    else cat(format(x), "\n")
  }
  invisible(NULL)
}
