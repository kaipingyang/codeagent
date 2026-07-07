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

# Per-chat gate context registry. `.register_all_tools()` may run more than once
# on the SAME chat (e.g. the Shiny app re-registers to wire shiny_ask_fn AFTER the
# client was built). ellmer's `on_tool_request` ACCUMULATES callbacks, so a naive
# re-install would leave a stale first gate (built before shiny_ask_fn -> "ask"
# with no ask_fn -> deny) racing the real one. We therefore install exactly ONE
# gate per chat and have it read a MUTABLE context (mode/ask_fn/policy/hooks), so
# re-registration just updates the context instead of stacking a second gate.
.gate_contexts <- new.env(parent = emptyenv())

# Generic "run once per (chat, key)" guard. Several callbacks are registered from
# .register_all_tools(), which the Shiny app runs more than once on the same chat;
# ellmer's on_tool_request/on_tool_result ACCUMULATE, so callbacks that should be
# singletons (the permission gate, mid-loop compaction, ...) must guard with this.
# Returns TRUE the first time for a given chat+key, FALSE afterwards.
.chat_callbacks_installed <- new.env(parent = emptyenv())
#' @keywords internal
.chat_once <- function(chat, key) {
  addr <- tryCatch(rlang::obj_address(chat), error = function(e) NULL) %||% "default"
  k <- paste0(addr, ":", key)
  if (isTRUE(.chat_callbacks_installed[[k]])) return(FALSE)
  .chat_callbacks_installed[[k]] <- TRUE
  TRUE
}

# Build the gate callback from a live context env (`ctx`). Reads ctx$policy,
# ctx$mode_env, ctx$rules, ctx$ask_fn, ctx$hooks at call time. Returns invisible()
# to allow, raises `ellmer::tool_reject()` to deny (sync), or returns a promise
# (async/Shiny). Fires PreToolUse + PermissionDenied hooks. Unit-testable.
#' @keywords internal
.tool_gate_fn <- function(policy_or_ctx, mode_env = NULL, rules = list(),
                          ask_fn = NULL, hooks = NULL) {
  ctx <- if (is.environment(policy_or_ctx)) policy_or_ctx
         else .make_gate_ctx(policy_or_ctx, mode_env, rules, ask_fn, hooks)
  force(ctx)
  resolve_mode <- function() {
    m <- ctx$mode_env
    if (is.environment(m)) m$mode %||% "default" else (m %||% "default")
  }
  deny <- function(name, input, reason) {
    if (!is.null(ctx$hooks))
      tryCatch(ctx$hooks$run_permission_denied(name, input, resolve_mode()),
               error = function(e) NULL)
    ellmer::tool_reject(paste0("Permission denied for ", name,
                               if (nzchar(reason)) paste0(" (", reason, ")") else ""))
  }

  function(request) {
    name  <- tryCatch(request@name, error = function(e) NULL)
    if (is.null(name) || !nzchar(name)) return(invisible())
    input <- tryCatch(as.list(request@arguments), error = function(e) list())
    tool  <- tryCatch(request@tool, error = function(e) NULL)

    if (!is.null(ctx$hooks))
      tryCatch(ctx$hooks$run_pre(name, input), error = function(e) NULL)  # PreToolUse

    ov  <- ctx$policy$overrides[[name]]
    cap <- .tool_capability(name, tool)
    # benign (read/meta) tools with no explicit override: allow, don't gate.
    if (is.null(ov) && identical(cap, "read")) return(invisible())

    decision <- tryCatch(
      .gate_decide(name, input, ctx$policy, resolve_mode(), ctx$rules, cap),
      error = function(e) "allow")

    if (identical(decision, "allow")) return(invisible())
    if (identical(decision, "deny"))  return(deny(name, input, cap))

    # decision == "ask"
    ask_fn <- ctx$ask_fn
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

# Build a fresh gate context env (also used directly by tests).
#' @keywords internal
.make_gate_ctx <- function(policy, mode_env, rules = list(),
                           ask_fn = NULL, hooks = NULL) {
  ctx <- new.env(parent = emptyenv())
  ctx$policy   <- policy
  ctx$mode_env <- mode_env
  ctx$rules    <- rules
  ctx$ask_fn   <- ask_fn
  ctx$hooks    <- hooks
  ctx$installed <- FALSE
  ctx
}

#' Install the central permission gate on a Chat (idempotent per chat)
#'
#' Registers ONE `on_tool_request` callback (+ one `on_tool_result` for PostToolUse)
#' that gates every tool by name. Safe to call repeatedly on the same chat: the
#' first call installs the callbacks; later calls only refresh the live context
#' (mode / ask_fn / policy / hooks), so the Shiny path can wire `shiny_ask_fn`
#' after the client was built without stacking a second (denying) gate.
#'
#' Works for sync (`$chat()`) and async (`$chat_async()`/Shiny): when the decision
#' is `"ask"` and `ask_fn` returns a promise, the gate returns a promise the async
#' loop awaits (UI approval); a logical `ask_fn` is handled inline.
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
.install_permission_gate <- function(chat, settings, mode_env,
                                     rules = list(), ask_fn = NULL, hooks = NULL) {
  key <- tryCatch(rlang::obj_address(chat), error = function(e) NULL) %||% "default"
  ctx <- .gate_contexts[[key]]
  if (is.null(ctx)) {
    ctx <- .make_gate_ctx(.resolve_tool_policy(settings), mode_env, rules, ask_fn, hooks)
    .gate_contexts[[key]] <- ctx
  } else {
    # refresh live context (mode/ask_fn/policy/hooks may have changed)
    ctx$policy <- .resolve_tool_policy(settings); ctx$mode_env <- mode_env
    ctx$rules  <- rules; ctx$ask_fn <- ask_fn; ctx$hooks <- hooks
  }
  if (isTRUE(ctx$installed)) return(invisible(chat))   # gate already on this chat
  ctx$installed <- TRUE

  tryCatch(chat$on_tool_request(.tool_gate_fn(ctx)), error = function(e) NULL)
  tryCatch(chat$on_tool_result(function(result) {      # PostToolUse (reads ctx live)
    if (is.null(ctx$hooks)) return(invisible())
    nm <- tryCatch(result@request@name, error = function(e) "")
    tryCatch(ctx$hooks$run_post(nm, list(), result), error = function(e) NULL)
  }), error = function(e) NULL)
  invisible(chat)
}
