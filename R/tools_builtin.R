#' @title Built-in Tools Registration
#' @description Registers all core codeagent tools (Bash, Read, Write, Edit,
#'   MultiEdit, Glob, Grep, LS) onto an ellmer Chat. Individual tool factories
#'   live in dedicated files: [tools_bash], [tools_fs], [tools_search].
#'
#'   Shared helpers used by all tool files:
#'   * `.tool_result()` -- legacy ContentToolResult builder
#'   * `.make_permission_checker()` -- live-mode permission closure factory
#' @name tools_builtin
#' @keywords internal
NULL

# ---------------------------------------------------------------------------
# Shared tool factory helpers  (used by tools_bash.R, tools_fs.R, etc.)
# ---------------------------------------------------------------------------

# Wrap a tool result string in ContentToolResult with display metadata.
.tool_result <- function(text, title = NULL, markdown = NULL,
                          right_output = NULL) {
  display <- list()
  if (!is.null(title))        display$title        <- htmltools::HTML(title)
  if (!is.null(markdown))     display$markdown     <- markdown
  if (!is.null(right_output)) display$right_output <- right_output
  if (length(display) == 0L)  display <- NULL
  ellmer::ContentToolResult(
    value = text,
    extra = if (!is.null(display)) list(display = display) else list()
  )
}

# Build the permission-checking closure used inside tool factories.
# `mode` may be a static string OR a "mode environment" with a live `$mode`
# slot (set by plan-mode tools so all already-registered checkers see it).
.make_permission_checker <- function(tool_name, mode, rules,
                                      ask_fn = NULL) {
  resolve_mode <- function() {
    if (is.environment(mode)) mode$mode %||% "default" else mode
  }
  function(tool_input) {
    decision <- check_permission(tool_name, resolve_mode(), rules, tool_input)
    if (decision == "allow") return(TRUE)
    if (decision == "deny")  return(FALSE)
    if (!is.null(ask_fn)) return(isTRUE(ask_fn(tool_name, tool_input)))
    FALSE
  }
}

# ---------------------------------------------------------------------------
# Registration
# ---------------------------------------------------------------------------

#' Register all built-in codeagent tools to a Chat
#'
#' @param chat An `ellmer::Chat` object.
#' @param mode Character. Permission mode (see [PermissionMode]).
#' @param rules List. [PermissionRule()] objects.
#' @param ask_fn Function or NULL. `function(tool_name, input) -> logical`.
#'   Called when permission is `"ask"`.
#' @param skip_file_tools Logical. Skip Read/Write/Edit/MultiEdit/Glob/Grep/LS
#'   (register only Bash) when btw file tools handle files (Path A).
#' @param sandbox List or NULL. Bash sandbox profile (see [.sandbox_profile()]);
#'   passed through to [bash_tool()].
#' @return Invisibly returns `chat`.
#' @export
register_builtin_tools <- function(chat, mode = "default",
                                    rules = list(), ask_fn = NULL,
                                    skip_file_tools = FALSE,
                                    sandbox = NULL) {
  chat$register_tool(bash_tool(mode, rules, ask_fn, sandbox = sandbox))
  if (!isTRUE(skip_file_tools)) {
    chat$register_tool(read_tool(mode, rules))
    chat$register_tool(write_tool(mode, rules, ask_fn))
    chat$register_tool(edit_tool(mode, rules, ask_fn))
    chat$register_tool(multi_edit_tool(mode, rules, ask_fn))
    chat$register_tool(glob_tool())
    chat$register_tool(grep_tool())
    chat$register_tool(ls_tool())
  }
  invisible(chat)
}
