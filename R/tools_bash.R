#' @title Bash Tool
#' @description Execute shell commands with permission gating and optional sandboxing.
#'   Shared helpers (`.tool_result`, `.make_permission_checker`) live in
#'   `tools_builtin.R` and are available to all tool files.
#' @name tools_bash
#' @keywords internal
NULL

# ---------------------------------------------------------------------------
# Bash tool
# ---------------------------------------------------------------------------

#' Create the Bash tool
#'
#' @param mode Character. Permission mode (see [PermissionMode]).
#' @param rules List. [PermissionRule()] objects.
#' @param ask_fn Function or NULL. `function(tool_name, input) -> logical`.
#'   Called when permission is `"ask"`.
#' @param sandbox List or NULL. Bash sandbox profile (see [.sandbox_profile()]):
#'   `list(enabled, allow_network, keep_env)`. When enabled, scrubs the command
#'   environment and can block network utilities.
#' @return An `ellmer::tool()` object.
#' @export
bash_tool <- function(mode = "default", rules = list(), ask_fn = NULL,
                      sandbox = NULL) {
  checker  <- .make_permission_checker("Bash", mode, rules, ask_fn)
  sb_prof  <- .sandbox_profile(list(sandbox = sandbox))

  ellmer::tool(
    name = "Bash",
    fun = function(command, timeout = .BASH_TIMEOUT_DEFAULT,
                   description = NULL, run_in_background = FALSE,
                   `_intent` = NULL) {
      if (!checker(list(command = command))) {
        ellmer::tool_reject(paste0("Permission denied for Bash command: ", command))
      }
      # Sandbox: refuse network commands when network is disabled.
      blocked <- .sandbox_block_reason(command, sb_prof)
      if (!is.null(blocked)) {
        ellmer::tool_reject(paste0("Sandbox blocked: ", blocked, ". Command: ", command))
      }
      sb_env <- .sandbox_env(sb_prof)   # NULL = inherit; character() = scrubbed
      # Fire-and-forget: do not capture output, do not block.
      if (isTRUE(run_in_background)) {
        tmp <- tempfile(fileext = ".sh")
        writeLines(command, tmp)
        system2("bash", tmp, wait = FALSE, stdout = FALSE, stderr = FALSE,
                env = sb_env %||% character())
        return(.tool_result2(paste0("[Background: command started]\nCommand: ", command),
                             kind = "text", icon = "terminal",
                             title = sprintf("Bash (bg) <code>%s</code>",
                                             substr(command, 1L, 60L)),
                             payload = list(text = command, lang = "sh")))
      }
      tryCatch({
        # Write command to temp file so shell quote nesting is never an issue
        tmp <- tempfile(fileext = ".sh")
        on.exit(unlink(tmp), add = TRUE)
        writeLines(command, tmp)
        out <- system2(
          "bash", tmp,
          stdout = TRUE, stderr = TRUE,
          timeout = as.numeric(timeout),
          env = sb_env %||% character()
        )
        status <- attr(out, "status") %||% 0L
        result <- paste(out, collapse = "\n")
        if (!is.null(status) && status != 0L)
          result <- paste0(result, "\n[exit status: ", status, "]")
        result <- truncate_tool_result(result, "Bash")
        label  <- substr(command, 1L, 80L)
        if (nchar(command) > 80L) label <- paste0(label, "...")
        .tool_result2(result,
                      kind     = "text",
                      icon     = "terminal",
                      title    = sprintf("<code>%s</code>",
                                         htmltools::htmlEscape(label)),
                      markdown = sprintf("```sh\n%s\n```\n\n%s", command, result),
                      payload  = list(text = result, lang = "sh"))
      }, error = function(e) {
        paste0("[Error] ", conditionMessage(e))
      })
    },
    description = paste0(
      "Execute a shell (bash) command. Use for file operations, running tests, ",
      "installing packages, git commands, etc. ",
      "Prefer over chained R calls when shell utilities are more appropriate. ",
      "NEVER use 'Rscript -e ...' to run R code -- shell quote nesting will always fail. ",
      "To run R code: ALWAYS use the Write tool to save code to /tmp/script.R first, ",
      "then run 'Rscript /tmp/script.R' with this tool."
    ),
    arguments = list(
      command     = ellmer::type_string(
        "The shell command to execute.", required = TRUE),
      timeout     = ellmer::type_number(
        "Timeout in seconds (default 30).", required = FALSE),
      description = ellmer::type_string(
        "Short description of what this command does (shown to user).",
        required = FALSE),
      run_in_background = ellmer::type_boolean(
        "Run in background (fire-and-forget).", required = FALSE),
      `_intent` = ellmer::type_string(
        "Brief description of why this command is being run.", required = FALSE)
    ),
    annotations = ellmer::tool_annotations(
      title            = "Bash",
      read_only_hint   = FALSE,
      destructive_hint = TRUE
    )
  )
}
