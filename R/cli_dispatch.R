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
#' Determines which subcommand to run given raw positional argv and the
#' `print_mode` flag.  Used by `exec/codeagent.R` to keep dispatch logic
#' testable.
#'
#' Rules (in order):
#' 1. If `argv[[1]]` is a known subcommand name, use it.
#' 2. If `print_mode = TRUE` or `argv` is non-empty, treat as a one-shot
#'    `run` (the prompt comes from `argv`).
#' 3. Otherwise default to `chat` (interactive REPL).
#'
#' @param argv Character vector of positional arguments (no flags).
#' @param print_mode Logical. TRUE when `-p`/`--print` was passed.
#' @return Named list: `cmd` (character), `rest` (character vector).
#' @keywords internal
.ca_dispatch <- function(argv = character(), print_mode = FALSE) {
  known <- c("run", "chat", "repl", "app", "skills", "mcp", "info")
  argv  <- as.character(argv %||% character())
  if (length(argv) && argv[[1L]] %in% known)
    return(list(cmd = argv[[1L]], rest = argv[-1L]))
  if (isTRUE(print_mode) || length(argv) > 0L)
    return(list(cmd = "run", rest = argv))
  list(cmd = "chat", rest = character())
}
