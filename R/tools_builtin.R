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

# Wrap a (synchronous, bypass-built) tool in an async permission gate for the
# Shiny UI path. The returned tool's `fun` returns a promise<ContentToolResult>
# that ellmer's `invoke_tools_async()` awaits (verified against ellmer 0.4.x).
#
# The gate runs the real `check_permission()` (using the live `mode`), and when
# the decision is "ask" it awaits the promise from `ask_fn` (the Shiny approval
# bar). If allowed it delegates to `inner_tool` (built with mode="bypass" so its
# own checker always passes); otherwise it emits `ellmer::tool_reject()`.
#
# Why not `coro::async`: coro requires a *literal* anonymous function, so it
# cannot wrap a dynamically-built function with copied formals. Returning a
# `promises::then()` promise from a plain function achieves the same await
# without coro, and keeps the tool's formals/arguments intact for ellmer.
#
# Only used when a promise-returning `ask_fn` is supplied (Shiny). The sync CLI
# path never calls this, so `chat$chat()` tool execution stays synchronous.
.asyncify_gated_tool <- function(inner_tool, tool_name, mode, rules,
                                 ask_fn = NULL) {
  async_checker <- function(tool_input) {
    resolve_mode <- if (is.environment(mode)) (mode$mode %||% "default") else mode
    decision     <- check_permission(tool_name, resolve_mode, rules, tool_input)
    if (identical(decision, "allow")) return(promises::promise_resolve(TRUE))
    if (identical(decision, "deny"))  return(promises::promise_resolve(FALSE))
    if (!is.null(ask_fn)) {
      res <- ask_fn(tool_name, tool_input)
      if (inherits(res, "promise")) return(res)
      return(promises::promise_resolve(isTRUE(res)))
    }
    promises::promise_resolve(FALSE)
  }
  body_expr <- quote({
    .args <- as.list(environment())
    promises::then(async_checker(.args), function(.allowed) {
      if (isTRUE(.allowed)) do.call(inner_tool, .args)
      else ellmer::tool_reject(paste0("Permission denied for ", tool_name))
    })
  })
  wrapped <- rlang::new_function(formals(inner_tool), body_expr,
                                 env = environment())
  ellmer::tool(
    fun         = wrapped,
    name        = tool_name,
    description = inner_tool@description,
    arguments   = inner_tool@arguments@properties,
    annotations = inner_tool@annotations
  )
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
#' @param skip_file_tools Logical. If `TRUE`, skip Read/Write/Edit/MultiEdit/Glob/Grep/LS
#'   and register only Bash. Advanced use: set this if you want btw file tools to be
#'   the *only* file tools (no absolute-path fallback). Default `FALSE` means both
#'   codeagent and btw file tools coexist when Path A is enabled.
#' @param sandbox List or NULL. Bash sandbox profile (see [.sandbox_profile()]);
#'   passed through to [bash_tool()].
#' @return Invisibly returns `chat`.
#' @export
register_builtin_tools <- function(chat, mode = "default",
                                    rules = list(), ask_fn = NULL,
                                    skip_file_tools = FALSE,
                                    sandbox = NULL, async = FALSE) {
  # Async (Shiny) path: build each gated tool with mode="bypass" (so its own
  # checker always passes) and wrap it in .asyncify_gated_tool(), which runs the
  # real permission check + awaits the promise-returning ask_fn. Sync path keeps
  # the original in-fun gate. Read-only tools (Read/Glob/Grep/LS) never gate, so
  # they are identical in both paths.
  reg_gated <- function(inner, tname) {
    if (isTRUE(async))
      chat$register_tool(.asyncify_gated_tool(inner, tname, mode, rules, ask_fn))
    else
      chat$register_tool(inner)
  }
  inner_mode <- if (isTRUE(async)) "bypass" else mode
  inner_ask  <- if (isTRUE(async)) NULL else ask_fn

  reg_gated(bash_tool(inner_mode, rules, inner_ask, sandbox = sandbox), "Bash")
  if (!isTRUE(skip_file_tools)) {
    chat$register_tool(read_tool(mode, rules))
    reg_gated(write_tool(inner_mode, rules, inner_ask), "Write")
    reg_gated(edit_tool(inner_mode, rules, inner_ask), "Edit")
    reg_gated(multi_edit_tool(inner_mode, rules, inner_ask), "MultiEdit")
    chat$register_tool(glob_tool())
    chat$register_tool(grep_tool())
    chat$register_tool(ls_tool())
  }
  invisible(chat)
}
