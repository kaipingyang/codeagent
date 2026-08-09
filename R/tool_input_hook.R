#' @title Tool input rewrite (PreToolUse updatedInput)
#' @description Lets a PreToolUse hook rewrite a tool's arguments before it
#'   executes, aligning with the Claude Agent SDK's `updatedInput` contract.
#'   ellmer's `on_tool_request` is rejectable-only (a callback can deny but not
#'   rewrite the request), so the rewrite is done one layer in: each tool
#'   function is wrapped in a closure that runs `HookRegistry$run_pre()` and, if
#'   a hook returned `updated_input`, calls the original with the new arguments.
#'
#'   Execution order is `gate (on_tool_request) -> this wrapper -> original`, so
#'   the permission gate always sees the ORIGINAL arguments (a rewrite cannot
#'   bypass permission checks -- matching the SDK's permission-then-updatedInput
#'   ordering). The tool's JSON schema is unaffected: ellmer derives it from the
#'   `@arguments` slot, independent of the wrapped function's formals.
#' @name tool_input_hook
#' @keywords internal
NULL

# Wrap one ToolDef so a PreToolUse hook can rewrite its arguments or deny it.
# Re-wrapping unwraps to the original first (no nested hook layers). No-op when
# hooks is NULL or the tool has no underlying function.
#' @keywords internal
.wrap_tool_pre_hook <- function(tool, hooks) {
  if (is.null(hooks)) return(tool)
  current <- tryCatch(S7::S7_data(tool), error = function(e) NULL)
  if (!is.function(current)) return(tool)
  # Idempotent: if already wrapped for these hooks, leave as-is.
  if (identical(attr(current, "pre_hook_state"), hooks)) return(tool)
  original  <- attr(current, "pre_hook_original") %||% current
  tool_name <- tryCatch(S7::prop(tool, "name"), error = function(e) NA_character_)

  wrapped <- function(...) {
    args <- list(...)
    r <- tryCatch(hooks$run_pre(tool_name, args), error = function(e) NULL)
    if (!is.null(r)) {
      if (identical(r[["action"]], "deny"))
        return(ellmer::tool_reject(r[["message"]] %||% "Blocked by PreToolUse hook."))
      # run_pre returns list(action="allow", input=<possibly rewritten args>).
      if (!is.null(r[["input"]]) && is.list(r[["input"]])) args <- r[["input"]]
    }
    do.call(original, args)
  }
  attr(wrapped, "pre_hook_wrapped")  <- TRUE
  attr(wrapped, "pre_hook_original") <- original
  attr(wrapped, "pre_hook_state")    <- hooks
  tryCatch({ S7::S7_data(tool) <- wrapped }, error = function(e) NULL)
  tool
}

# Wrap every tool currently on a Chat with the PreToolUse rewrite layer.
# Called from .register_all_tools after all tools are registered, BEFORE the
# permission gate is installed. No-op when hooks is NULL.
#' @keywords internal
.install_tool_input_hooks <- function(chat, hooks) {
  if (is.null(hooks)) return(invisible(chat))
  tools <- tryCatch(chat$get_tools(), error = function(e) list())
  if (!length(tools)) return(invisible(chat))
  wrapped <- lapply(tools, function(t) .wrap_tool_pre_hook(t, hooks))
  tryCatch(chat$set_tools(wrapped), error = function(e) NULL)
  invisible(chat)
}
