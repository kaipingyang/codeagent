#' @title Lint and format tools (lintr + styler)
#' @description codeagent-authored tools that let the agent statically analyse
#'   (lintr) and auto-format (styler) the R code it writes, and a lint-based
#'   `verify_fn` for the agent loop's verification step.
#' @name tools_lint
#' @keywords internal
NULL

# Core lint logic (separated from the ellmer tool wrapper so it is unit-testable
# without reaching into the ToolDef object).
#' @keywords internal
.lint_impl <- function(path) {
  if (!requireNamespace("lintr", quietly = TRUE))
    return(.tool_result2(
      "[Error] The 'lintr' package is not installed (install.packages('lintr')).",
      kind = "error", icon = "exclamation-triangle",
      title = "Lint - unavailable", payload = list(available = FALSE)))
  lints <- tryCatch(
    if (dir.exists(path)) lintr::lint_dir(path) else lintr::lint(path),
    error = function(e) e)
  if (inherits(lints, "error"))
    return(.tool_result2(paste("[Error]", conditionMessage(lints)),
      kind = "error", icon = "exclamation-triangle",
      title = "Lint - error", payload = list()))
  df <- as.data.frame(lints)
  if (nrow(df) == 0L)
    return(.tool_result2("No lints found.", icon = "check-circle",
      title = "Lint - clean", payload = list(count = 0L)))
  lines <- sprintf("%s:%s:%s [%s] %s",
                   df$filename, df$line_number, df$column_number,
                   df$type, df$message)
  .tool_result2(
    paste0(nrow(df), " lint(s) found:\n", paste(lines, collapse = "\n")),
    icon = "list-check",
    title = sprintf("Lint - %d issue(s)", nrow(df)),
    payload = list(count = nrow(df)))
}

# Core format logic (see .lint_impl note on separation).
#' @keywords internal
.format_impl <- function(path) {
  if (!requireNamespace("styler", quietly = TRUE))
    return(.tool_result2(
      "[Error] The 'styler' package is not installed (install.packages('styler')).",
      kind = "error", icon = "exclamation-triangle",
      title = "Format - unavailable", payload = list(available = FALSE)))
  res <- tryCatch(
    if (dir.exists(path)) styler::style_dir(path) else styler::style_file(path),
    error = function(e) e)
  if (inherits(res, "error"))
    return(.tool_result2(paste("[Error]", conditionMessage(res)),
      kind = "error", icon = "exclamation-triangle",
      title = "Format - error", payload = list()))
  changed <- tryCatch(sum(res$changed %in% TRUE), error = function(e) NA_integer_)
  .tool_result2(
    sprintf("Formatted %s (%s file(s) changed).", path,
            if (is.na(changed)) "?" else changed),
    icon = "magic", title = "Format",
    payload = list(changed = changed))
}

# Lint an R file or directory with lintr. Read-only.
#' @keywords internal
lint_tool <- function() {
  ellmer::tool(
    fun = function(path) .lint_impl(path),
    name = "Lint",
    description = paste0(
      "Run lintr static analysis on an R file or directory and return ",
      "file:line:col diagnostics. Use it to check R code you just wrote or ",
      "edited for style and correctness issues before finishing."),
    arguments = list(
      path = ellmer::type_string(
        "Path to an R file or directory to lint.", required = TRUE)),
    annotations = ellmer::tool_annotations(title = "Lint", read_only_hint = TRUE)
  )
}

# Reformat R code to tidyverse style with styler. Modifies files in place.
#' @keywords internal
format_tool <- function() {
  ellmer::tool(
    fun = function(path) .format_impl(path),
    name = "Format",
    description = paste0(
      "Reformat R code to tidyverse style with styler. Modifies the file(s) in ",
      "place. Pass a single R file or a directory path."),
    arguments = list(
      path = ellmer::type_string(
        "Path to an R file or directory to reformat.", required = TRUE)),
    annotations = ellmer::tool_annotations(title = "Format", read_only_hint = FALSE)
  )
}

#' Register the Lint and Format tools to a Chat
#' @param chat An `ellmer::Chat` object.
#' @return Invisibly returns `chat`.
#' @keywords internal
register_lint_tools <- function(chat) {
  tryCatch(chat$register_tool(lint_tool()),   error = function(e) NULL)
  tryCatch(chat$register_tool(format_tool()), error = function(e) NULL)
  invisible(chat)
}

#' Lint-based verification function
#'
#' Runs `lintr` on `path` (relative to `cwd`) and reports any lints as a
#' verification failure, so the agent loop re-enters to fix them. Use as
#' `verify_fn` in [codeagent_client()] / [agent_loop()], on its own or combined
#' with [verify_r_tests()].
#'
#' @param path Character. File or directory to lint, relative to `cwd`
#'   (default `"R"`).
#' @return A function suitable for `verify_fn`.
#' @export
verify_r_lints <- function(path = "R") {
  function(response, chat, cwd) {
    if (!requireNamespace("lintr", quietly = TRUE)) return(list(passed = TRUE))
    tryCatch({
      target <- file.path(cwd, path)
      lints  <- if (dir.exists(target)) lintr::lint_dir(target) else lintr::lint(target)
      n <- length(lints)
      list(
        passed  = n == 0L,
        message = if (n > 0L)
          sprintf("%d lint(s) found. Run lintr::lint_dir(\"%s\") and fix them.", n, path)
        else "")
    }, error = function(e) list(passed = TRUE))  # never block on lint infra errors
  }
}
