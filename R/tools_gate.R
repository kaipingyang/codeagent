#' @title Unified tool permission gate
#' @description A single central gate registered via `chat$on_tool_request()` that
#'   governs EVERY tool call (codeagent-native, btw, Format, MCP) uniformly by
#'   tool name -- mirroring Claude Code's central tool-execution pipeline.
#'
#'   ellmer already supports a rejectable central hook: `invoke_tools()` runs
#'   `maybe_on_tool_request(request, cb)` which is
#'   `tryCatch({cb(request); NULL}, ellmer_tool_reject = \(e) ContentToolResult(error=...))`;
#'   a non-NULL result makes the loop skip the tool (`next`). The async loop does
#'   `coro::await(cb(request))` inside the same tryCatch, so a promise-returning
#'   callback can gate the Shiny path too. This gate therefore replaces the old
#'   per-tool embedded checkers (tools built with `mode = "bypass"`).
#' @name tools_gate
#' @keywords internal
NULL

# Per-tool capability metadata (CC-style tool.isReadOnly/isDestructive). Tools not
# listed fall back to the tool's own `read_only_hint` annotation (conservative:
# unknown -> "write").
.TOOL_META <- list(
  # codeagent-native
  Bash        = list(set = "A", capability = "exec"),
  RunR        = list(set = "A", capability = "exec"),
  Write       = list(set = "A", capability = "write"),
  Edit        = list(set = "A", capability = "write"),
  MultiEdit   = list(set = "A", capability = "write"),
  Format      = list(set = "A", capability = "write"),
  Read        = list(set = "A", capability = "read"),
  Glob        = list(set = "A", capability = "read"),
  Grep        = list(set = "A", capability = "read"),
  LS          = list(set = "A", capability = "read"),
  Lint        = list(set = "A", capability = "read"),
  # btw file tools (set B)
  btw_tool_files_write   = list(set = "B", capability = "write"),
  btw_tool_files_edit    = list(set = "B", capability = "write"),
  btw_tool_files_replace = list(set = "B", capability = "write"),
  btw_tool_files_patch   = list(set = "B", capability = "write"),
  btw_tool_files_read    = list(set = "B", capability = "read"),
  btw_tool_files_list    = list(set = "B", capability = "read"),
  btw_tool_files_search  = list(set = "B", capability = "read"),
  # other write-capable btw tools
  btw_tool_git_commit         = list(set = "B", capability = "write"),
  btw_tool_git_branch_create  = list(set = "B", capability = "write"),
  btw_tool_git_branch_checkout = list(set = "B", capability = "write"),
  btw_tool_github             = list(set = "B", capability = "net"),
  btw_tool_pkg_install        = list(set = "B", capability = "exec")
)

# Resolve a tool's capability. Only tools explicitly listed in .TOOL_META are
# treated as sensitive (write/exec/net); everything else defaults to "read"
# (allow) so benign/meta tools (todo, skill, remember, read-only btw, ...) are not
# accidentally gated. Fine-grained control over any tool is still possible via
# settings$tools$overrides.
#' @keywords internal
.tool_capability <- function(name, tool = NULL) {
  m <- .TOOL_META[[name]]
  if (!is.null(m)) return(m$capability)
  "read"
}

# Parse settings$tools into a policy object (sets / capabilities / overrides).
#' @keywords internal
.resolve_tool_policy <- function(settings) {
  t <- settings$tools %||% list()
  list(
    sets         = t$sets %||% c("A", "B"),
    capabilities = t$capabilities %||% list(),
    overrides    = t$overrides %||% list()
  )
}

# Decide allow/deny/ask for a tool call. Precedence: per-tool override >
# capability-level policy > mode/rules permission (check_permission).
#' @keywords internal
.gate_decide <- function(name, input, policy, mode, rules, capability) {
  ov <- policy$overrides[[name]]
  if (!is.null(ov) && nzchar(ov)) return(ov)
  cap <- policy$capabilities[[capability]]
  if (!is.null(cap) && nzchar(cap)) return(cap)
  check_permission(name, mode, rules, input)
}

#' Install the central permission gate on a Chat
#'
#' Registers one `on_tool_request` callback that gates every tool by name, plus
#' an `on_tool_result` callback for PostToolUse hooks. Works for the sync
#' (`$chat()`) and async (`$chat_async()`/Shiny) paths: when the decision is
#' `"ask"` and `ask_fn` returns a promise, the gate returns a promise that the
#' async loop awaits (UI approval); a logical `ask_fn` is handled inline.
#'
#' @param chat An `ellmer::Chat`.
#' @param settings Named list (for `settings$tools` policy).
#' @param mode_env Environment with `$mode` (live permission mode) or a string.
#' @param rules List of fine-grained permission rules.
#' @param ask_fn `function(name, input)` returning logical or promise<logical>,
#'   or NULL (then `"ask"` becomes deny).
#' @param hooks A `HookRegistry` or NULL (fires PreToolUse/PostToolUse/PermissionDenied).
#' @return Invisibly `chat`.
#' @keywords internal
# Build the gate callback (extracted so it is unit-testable in isolation). Returns
# a `function(request)` suitable for `chat$on_tool_request()`: returns invisible()
# to allow, raises `ellmer::tool_reject()` to deny (sync), or returns a promise
# that resolves/rejects (async/Shiny). Fires PreToolUse + PermissionDenied hooks.
#' @keywords internal
.tool_gate_fn <- function(policy, resolve_mode, rules = list(),
                          ask_fn = NULL, hooks = NULL) {
  force(policy); force(resolve_mode); force(rules); force(ask_fn); force(hooks)

  deny <- function(name, input, reason) {
    if (!is.null(hooks))
      tryCatch(hooks$run_permission_denied(name, input, resolve_mode()),
               error = function(e) NULL)
    ellmer::tool_reject(paste0("Permission denied for ", name,
                               if (nzchar(reason)) paste0(" (", reason, ")") else ""))
  }

  function(request) {
    name  <- tryCatch(request@name, error = function(e) NULL)
    if (is.null(name) || !nzchar(name)) return(invisible())
    input <- tryCatch(as.list(request@arguments), error = function(e) list())
    tool  <- tryCatch(request@tool, error = function(e) NULL)

    if (!is.null(hooks))
      tryCatch(hooks$run_pre(name, input), error = function(e) NULL)   # PreToolUse

    ov  <- policy$overrides[[name]]
    cap <- .tool_capability(name, tool)
    # benign (read/meta) tools with no explicit override: allow, don't gate.
    if (is.null(ov) && identical(cap, "read")) return(invisible())

    decision <- tryCatch(
      .gate_decide(name, input, policy, resolve_mode(), rules, cap),
      error = function(e) "allow")

    if (identical(decision, "allow")) return(invisible())
    if (identical(decision, "deny"))  return(deny(name, input, cap))

    # decision == "ask"
    res <- if (is.function(ask_fn)) tryCatch(ask_fn(name, input),
                                             error = function(e) FALSE) else FALSE
    if (inherits(res, "promise")) {                                   # async (Shiny)
      return(promises::then(res, function(ok) {
        if (isTRUE(ok)) invisible(NULL) else deny(name, input, cap)
      }))
    }
    if (isTRUE(res)) return(invisible())                              # sync approved
    deny(name, input, cap)
  }
}

.install_permission_gate <- function(chat, settings, mode_env,
                                     rules = list(), ask_fn = NULL, hooks = NULL) {
  policy <- .resolve_tool_policy(settings)
  resolve_mode <- function()
    if (is.environment(mode_env)) mode_env$mode %||% "default" else (mode_env %||% "default")
  gate <- .tool_gate_fn(policy, resolve_mode, rules, ask_fn, hooks)

  tryCatch(chat$on_tool_request(gate), error = function(e) NULL)

  if (!is.null(hooks)) {
    tryCatch(chat$on_tool_result(function(result) {
      nm <- tryCatch(result@request@name, error = function(e) "")
      tryCatch(hooks$run_post(nm, list(), result), error = function(e) NULL)  # PostToolUse
    }), error = function(e) NULL)
  }
  invisible(chat)
}
