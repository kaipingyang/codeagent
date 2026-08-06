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

# Mutable registry for host/third-party tools to declare their capability so the
# permission gate governs them correctly. Built-in .TOOL_META stays authoritative
# (a host cannot downgrade Bash); host tools (absent from .TOOL_META) fall through
# to here. Only the CONTENTS are mutated (the binding is locked after load) --
# same pattern as .gate_contexts / .chat_callbacks_installed in this file.
.tool_meta_user <- new.env(parent = emptyenv())

# Resolve a tool's capability. Precedence: built-in .TOOL_META > host registry
# (register_tool_meta) > default "read". Only tools resolving to write/exec/net are
# treated as sensitive; "read" (the default) is allowed WITHOUT gating, so benign
# tools (todo, skill, remember, read-only btw, host read-only tools, ...) are not
# accidentally gated. Fine-grained control over ANY tool is still possible via
# settings$tools$overrides.
#' @keywords internal
.tool_capability <- function(name, tool = NULL) {
  m <- .TOOL_META[[name]]
  if (!is.null(m)) return(m$capability)
  u <- .tool_meta_user[[name]]
  if (!is.null(u)) return(u$capability)
  "read"
}

#' Declare a host tool's permission capability
#'
#' @description
#' Register the permission **capability** of a tool that a host application
#' attaches to the chat (via `chat$register_tool()`), so codeagent's central
#' permission gate governs it like a native tool.
#'
#' codeagent classifies every tool call by capability. Built-in tools are known;
#' any **unregistered** tool defaults to `"read"` and is therefore allowed
#' **without gating**. If a host tool performs sensitive actions (writing files,
#' executing code, network access), declare it here so the gate can `ask`/`deny`
#' it under the active permission mode and `settings$tools` policy.
#'
#' Built-in tool metadata stays authoritative -- this only classifies tools not
#' already known to codeagent. Registrations persist for the R session.
#'
#' @param name Character(1). Tool name (must match the `ellmer::tool()` name).
#' @param capability One of `"read"`, `"write"`, `"exec"`, `"net"`. Use `"read"`
#'   for read-only/benign tools (allowed without prompting); `"write"`/`"exec"`/
#'   `"net"` route through the permission gate.
#' @param set Character(1). Optional grouping label for reporting (default `"C"`
#'   = host/custom). Not used in gate decisions.
#' @return Invisibly, `name`.
#' @examples
#' \dontrun{
#' chat$register_tool(my_run_code_tool)      # a host tool that executes R code
#' register_tool_meta("RunTFLCode", "exec")  # -> gated like Bash / RunR
#' }
#' @seealso [codeagent_client()], [register_builtin_tools()]
#' @export
register_tool_meta <- function(name,
                               capability = c("read", "write", "exec", "net"),
                               set = "C") {
  if (!is.character(name) || length(name) != 1L || !nzchar(name))
    stop("`name` must be a non-empty character(1).", call. = FALSE)
  capability <- match.arg(capability)
  .tool_meta_user[[name]] <- list(capability = capability, set = set)
  invisible(name)
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
    cap   <- .tool_capability(name, tool)

    if (!is.null(ctx$hooks))
      tryCatch(ctx$hooks$run_pre(name, input), error = function(e) NULL)  # PreToolUse

    # Data Shield ingress runs for EVERY tool before capability/read fast-paths.
    shield <- ctx$data_shield %||%
      tryCatch(attr(ctx$chat, "codeagent_data_shield"), error=function(e) NULL)
    tool_call_id <- tryCatch(request@id, error=function(e) NULL)
    shield_decision <- if (inherits(shield, "DataShield"))
      tryCatch(shield$scan_ingress(
        name, input, tool_call_id = tool_call_id, capability = cap),
        error=function(e) list(action="block", reason="Data Shield ingress failed safely"))
      else list(action="pass")

    continue_after_shield <- function(shield_decision) {
      if (identical(shield_decision$action, "block"))
        return(deny(name, input, shield_decision$reason %||% "Data Shield ingress blocked"))
      shield_ask <- identical(shield_decision$action, "ask")
      ov <- ctx$policy$overrides[[name]]
      if (!shield_ask && is.null(ov) && identical(cap, "read")) return(invisible())
      decision <- if (shield_ask) "ask" else tryCatch(
        .gate_decide(name, input, ctx$policy, resolve_mode(), ctx$rules, cap),
        error = function(e) "allow")
      if (identical(decision, "allow")) return(invisible())
      if (identical(decision, "deny")) return(deny(name, input, cap))

      ask_fn <- ctx$ask_fn
      res <- if (is.function(ask_fn)) {
        fmls <- names(formals(ask_fn))
        if ("id" %in% fmls || "..." %in% fmls)
          tryCatch(ask_fn(name, input, id=tool_call_id), error=function(e) FALSE)
        else tryCatch(ask_fn(name, input), error=function(e) FALSE)
      } else FALSE
      if (inherits(res, "promise"))
        return(promises::then(res, function(ok) {
          if (isTRUE(ok)) invisible(NULL) else deny(name, input, cap)
        }))
      if (isTRUE(res)) return(invisible())
      deny(name, input, cap)
    }

    if (inherits(shield_decision, "promise"))
      return(promises::then(
        shield_decision, continue_after_shield,
        function(e) deny(name,input,"Data Shield reviewer failed safely")))
    continue_after_shield(shield_decision)
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
  ctx$chat     <- NULL
  ctx$data_shield <- NULL
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
  shield <- settings$data_shield_engine %||% attr(chat, "codeagent_data_shield")
  if (is.null(ctx)) {
    ctx <- .make_gate_ctx(.resolve_tool_policy(settings), mode_env, rules, ask_fn, hooks)
    ctx$chat <- chat; ctx$data_shield <- shield
    .gate_contexts[[key]] <- ctx
  } else {
    # refresh live context (mode/ask_fn/policy/hooks/shield may have changed)
    ctx$policy <- .resolve_tool_policy(settings); ctx$mode_env <- mode_env
    ctx$rules  <- rules; ctx$ask_fn <- ask_fn; ctx$hooks <- hooks
    ctx$chat <- chat; ctx$data_shield <- shield
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

#' Install codeagent's central permission gate on an existing Chat
#'
#' @description
#' For hosts that build a harness-only client
#' (`codeagent_client(register_tools = FALSE)`) and attach their own domain
#' tools, then want those tools governed by codeagent's central permission gate.
#'
#' Declare each sensitive tool's capability with [register_tool_meta()] (or pass
#' `tool_meta` here), then call this once after attaching the tools. Tools whose
#' capability resolves to `"read"` are allowed without gating; `write`/`exec`/
#' `net` route through the gate under `permission_mode` + the `tools` policy.
#'
#' Idempotent per chat: calling again refreshes the live mode / ask_fn / policy
#' rather than stacking a second gate.
#'
#' @param chat An `ellmer::Chat`.
#' @param permission_mode Character. One of the 7 modes (default `"default"`).
#' @param rules List. Fine-grained permission rules (see [check_permission()]).
#' @param tools List. `settings$tools` policy (`sets` / `capabilities` /
#'   `overrides`).
#' @param ask_fn Function or NULL. Permission callback invoked when a tool needs
#'   approval; may return a logical or a promise (async / Shiny). Called as
#'   `ask_fn(name, input)`, or `ask_fn(name, input, id = <tool_call_id>)` if it
#'   declares an `id` argument or `...`.
#' @param tool_meta Named list mapping tool name -> capability
#'   (`"read"`/`"write"`/`"exec"`/`"net"`), a convenience for calling
#'   [register_tool_meta()] on each before installing the gate.
#' @return Invisibly, `chat`.
#' @seealso [register_tool_meta()], [codeagent_client()]
#' @examples
#' \dontrun{
#' client <- codeagent_client(chat, register_tools = FALSE)
#' chat$register_tool(my_write_tool)
#' install_permission_gate(
#'   chat, permission_mode = "default",
#'   tool_meta = list(MyWriteTool = "write"),
#'   ask_fn = function(name, input, id = NULL) host_prompt(id, name, input))
#' }
#' @export
install_permission_gate <- function(chat, permission_mode = "default",
                                    rules = list(), tools = list(),
                                    ask_fn = NULL, tool_meta = list()) {
  if (length(tool_meta)) {
    if (is.null(names(tool_meta)) || any(!nzchar(names(tool_meta))))
      stop("`tool_meta` must be a named list (tool name -> capability).",
           call. = FALSE)
    for (nm in names(tool_meta)) register_tool_meta(nm, tool_meta[[nm]])
  }
  mode_env <- new.env(parent = emptyenv())
  mode_env$mode <- permission_mode
  settings <- list(permission_mode = permission_mode, tools = tools)
  .install_permission_gate(chat, settings, mode_env, rules = rules,
                           ask_fn = ask_fn)
  invisible(chat)
}
