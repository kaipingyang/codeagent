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
#
# `recheck_fn` (kiro round-2 #1): when a hook REWRITES the args, the rewritten
# values never return to the central gate (which already ran on the original
# args). If given, recheck_fn(name, input) re-runs the gate's authority (Data
# Shield ingress + permission decide) on the FINAL args and returns
# "allow"/"deny"/"block"; anything but "allow" rejects the call. Only invoked
# when the args actually changed, so an un-rewritten call has zero overhead.
#' @keywords internal
.wrap_tool_pre_hook <- function(tool, hooks, recheck_fn = NULL) {
  if (is.null(hooks)) return(tool)
  current <- tryCatch(S7::S7_data(tool), error = function(e) NULL)
  if (!is.function(current)) return(tool)
  # ellmer ToolDef reconstruction may strip arbitrary function attributes, so
  # wrapper identity is also stored in the closure environment.
  current_env <- tryCatch(environment(current), error = function(e) NULL)
  current_state <- attr(current, "pre_hook_state") %||%
    if (is.environment(current_env))
      get0(".codeagent_pre_hook_state", current_env, inherits = FALSE) else NULL
  if (identical(current_state, hooks)) return(tool)
  original <- attr(current, "pre_hook_original") %||%
    if (is.environment(current_env))
      get0(".codeagent_pre_hook_original", current_env,
           inherits = FALSE, ifnotfound = current) else current
  tool_name <- tryCatch(S7::prop(tool, "name"), error = function(e) NA_character_)

  wrapped <- function(...) {
    args <- list(...)
    r <- tryCatch(hooks$run_pre(tool_name, args), error = function(e) NULL)
    if (!is.null(r)) {
      if (identical(r[["action"]], "deny"))
        return(ellmer::tool_reject(r[["message"]] %||% "Blocked by PreToolUse hook."))
      # run_pre returns list(action="allow", input=<possibly rewritten args>).
      if (!is.null(r[["input"]]) && is.list(r[["input"]]) && !identical(r[["input"]], args)) {
        args <- r[["input"]]
        # Args were REWRITTEN -> re-run the gate authority on the final args so a
        # hook cannot smuggle a denied/protected value past the gate (which only
        # saw the original args). recheck_fn now also SCRUBS the args
        # (value-match/PII) and returns them, so we execute with the scrubbed
        # version (kiro round-3: round-2 only ran the cheap ingress here).
        if (is.function(recheck_fn)) {
          rc <- tryCatch(recheck_fn(tool_name, args),
                         error = function(e) list(action = "block", input = args))
          if (!identical(rc$action, "allow"))
            return(ellmer::tool_reject(sprintf(
              "Rewritten tool arguments rejected on re-check (%s).", rc$action)))
          if (is.list(rc$input)) args <- rc$input   # execute with scrubbed args
        }
      }
    }
    do.call(original, args)
  }
  attr(wrapped, "pre_hook_wrapped")  <- TRUE
  attr(wrapped, "pre_hook_original") <- original
  attr(wrapped, "pre_hook_state")    <- hooks
  assign(".codeagent_pre_hook_state", hooks,
         envir = environment(wrapped))
  assign(".codeagent_pre_hook_original", original,
         envir = environment(wrapped))
  tryCatch({ S7::S7_data(tool) <- wrapped }, error = function(e) NULL)
  tool
}

# Wrap every tool currently on a Chat with the PreToolUse rewrite layer.
# Called from .register_all_tools after all tools are registered, BEFORE the
# permission gate is installed. No-op when hooks is NULL. The re-check closure
# resolves the chat's live gate context lazily (the gate is installed just after
# this), so a rewrite is re-validated against the same authority as the gate.
#' @keywords internal
.install_tool_input_hooks <- function(chat, hooks) {
  if (is.null(hooks)) return(invisible(chat))
  tools <- tryCatch(chat$get_tools(), error = function(e) list())
  if (!length(tools)) return(invisible(chat))
  recheck_fn <- function(name, input) {
    ctx <- tryCatch(.gate_ctx_for(chat), error = function(e) NULL)
    if (is.null(ctx)) return("allow")            # no gate installed -> nothing to enforce
    .gate_recheck(ctx, name, input)
  }
  wrapped <- lapply(tools, function(t) .wrap_tool_pre_hook(t, hooks, recheck_fn))
  ok <- tryCatch({ chat$set_tools(wrapped); TRUE }, error = function(e) FALSE)
  if (!isTRUE(ok))
    stop("tool-input-hook install: set_tools() failed; PreToolUse rewrite/re-check ",
         "layer is NOT active (fail-closed).", call. = FALSE)
  invisible(chat)
}
