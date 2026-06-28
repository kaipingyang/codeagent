#' @title Tool Hook System
#' @description Lifecycle hook system for codeagent.
#'   Supports PreToolUse, PostToolUse, PostToolUseFailure, PermissionDenied,
#'   UserMessage, AssistantMessage, and custom event hooks.
#' @name hooks
#' @keywords internal
NULL

# ---------------------------------------------------------------------------
# Event type constants
# ---------------------------------------------------------------------------

#' Hook event types
#'
#' Named list of lifecycle event names that can be hooked.
#'
#' * `PRE_TOOL_USE`          -- Before tool execution (can allow/deny/modify input)
#' * `POST_TOOL_USE`         -- After successful tool execution (can modify output)
#' * `POST_TOOL_USE_FAILURE` -- After a tool throws an error
#' * `PERMISSION_DENIED`     -- When a tool call is blocked by permissions
#' * `PERMISSION_REQUEST`    -- When permission mode is "ask" (bubble/default)
#' * `USER_MESSAGE`          -- When user sends a message to the agent
#' * `ASSISTANT_MESSAGE`     -- When the assistant produces a text response
#'
#' @export
HookEvent <- list(
  PRE_TOOL_USE          = "PreToolUse",
  POST_TOOL_USE         = "PostToolUse",
  POST_TOOL_USE_FAILURE = "PostToolUseFailure",
  PERMISSION_DENIED     = "PermissionDenied",
  PERMISSION_REQUEST    = "PermissionRequest",
  USER_MESSAGE          = "UserMessage",
  ASSISTANT_MESSAGE     = "AssistantMessage"
)

# ---------------------------------------------------------------------------
# HookRegistry R6 class
# ---------------------------------------------------------------------------

#' Tool hook registry
#'
#' Manages lifecycle hooks. Hooks are registered per event type and run in
#' registration order.
#'
#' ## PreToolUse callback: `function(tool_name, tool_input)`
#' Returns list with `action`:
#' * `"allow"` -- proceed normally
#' * `"deny"` -- block execution (add optional `message`)
#' * `"updated_input"` -- replace input with `input` field
#'
#' ## PostToolUse callback: `function(tool_name, tool_input, tool_output)`
#' Returns list with `action`:
#' * `"allow"` -- pass output unchanged
#' * `"updated_output"` -- replace output with `output` field
#'
#' ## PostToolUseFailure callback: `function(tool_name, tool_input, error_message)`
#' Return value ignored (informational only).
#'
#' ## PermissionDenied callback: `function(tool_name, tool_input, mode)`
#' Return value ignored (informational only).
#'
#' ## PermissionRequest callback: `function(tool_name, tool_input, mode)`
#' Returns list with `action`:
#' * `"allow"` -- grant permission
#' * `"deny"` -- reject
#' * NULL / `"ask"` -- fall through to default ask_fn
#'
#' ## UserMessage callback: `function(message)`
#' Return value ignored (informational only).
#'
#' ## AssistantMessage callback: `function(message)`
#' Return value ignored (informational only).
#'
#' @export
HookRegistry <- R6::R6Class(
  "HookRegistry",
  cloneable = FALSE,

  private = list(
    hooks = NULL   # named list of event → list of (pattern, fn, timeout_ms)
  ),

  public = list(

    #' @description Create a new registry.
    initialize = function() {
      private$hooks <- list()
      for (evt in unlist(HookEvent))
        private$hooks[[evt]] <- list()
    },

    #' @description Register a hook for an event.
    #' @param event Character. One of [HookEvent] values.
    #' @param fn Function. Hook callback.
    #' @param tool_pattern Character or NULL. Glob filter for tool name
    #'   (only applies to tool-related events).
    #' @param timeout_ms Integer. Max ms before warning (default 2000).
    register = function(event, fn, tool_pattern = NULL, timeout_ms = 2000L) {
      if (!event %in% unlist(HookEvent))
        stop("Unknown event: '", event, "'. Use HookEvent$*.", call. = FALSE)
      if (is.null(private$hooks[[event]])) private$hooks[[event]] <- list()
      private$hooks[[event]] <- c(
        private$hooks[[event]],
        list(list(pattern = tool_pattern, fn = fn,
                  timeout_ms = as.integer(timeout_ms)))
      )
      invisible(self)
    },

    # Legacy convenience methods -------------------------------------------------

    #' @description Register a PreToolUse hook (legacy shorthand).
    register_pre = function(fn, tool_pattern = NULL, timeout_ms = 2000L) {
      self$register(HookEvent$PRE_TOOL_USE, fn, tool_pattern, timeout_ms)
    },

    #' @description Register a PostToolUse hook (legacy shorthand).
    register_post = function(fn, tool_pattern = NULL, timeout_ms = 2000L) {
      self$register(HookEvent$POST_TOOL_USE, fn, tool_pattern, timeout_ms)
    },

    # Fire methods ---------------------------------------------------------------

    #' @description Fire PreToolUse hooks.
    run_pre = function(tool_name, tool_input) {
      current_input <- tool_input
      for (hook in private$hooks[[HookEvent$PRE_TOOL_USE]]) {
        if (!.hook_pattern_matches(hook$pattern, tool_name)) next
        result <- .run_hook_timed(hook$fn, hook$timeout_ms, tool_name, current_input)
        if (is.null(result)) next
        action <- result[["action"]] %||% "allow"
        if (identical(action, "deny"))
          return(list(action = "deny",
                      message = result[["message"]] %||% "Blocked by hook."))
        if (identical(action, "updated_input") && !is.null(result[["input"]]))
          current_input <- result[["input"]]
      }
      list(action = "allow", input = current_input)
    },

    #' @description Fire PostToolUse hooks.
    run_post = function(tool_name, tool_input, tool_output) {
      current_output <- tool_output
      for (hook in private$hooks[[HookEvent$POST_TOOL_USE]]) {
        if (!.hook_pattern_matches(hook$pattern, tool_name)) next
        result <- .run_hook_timed(hook$fn, hook$timeout_ms,
                                   tool_name, tool_input, current_output)
        if (is.null(result)) next
        if (identical(result[["action"]] %||% "allow", "updated_output") &&
            !is.null(result[["output"]]))
          current_output <- result[["output"]]
      }
      current_output
    },

    #' @description Fire PostToolUseFailure hooks (informational).
    run_failure = function(tool_name, tool_input, error_message) {
      for (hook in private$hooks[[HookEvent$POST_TOOL_USE_FAILURE]]) {
        if (!.hook_pattern_matches(hook$pattern, tool_name)) next
        .run_hook_timed(hook$fn, hook$timeout_ms,
                        tool_name, tool_input, error_message)
      }
      invisible(NULL)
    },

    #' @description Fire PermissionDenied hooks (informational).
    run_permission_denied = function(tool_name, tool_input, mode) {
      for (hook in private$hooks[[HookEvent$PERMISSION_DENIED]]) {
        if (!.hook_pattern_matches(hook$pattern, tool_name)) next
        .run_hook_timed(hook$fn, hook$timeout_ms, tool_name, tool_input, mode)
      }
      invisible(NULL)
    },

    #' @description Fire PermissionRequest hooks.
    #' Returns "allow", "deny", or NULL (fall through to ask_fn).
    run_permission_request = function(tool_name, tool_input, mode) {
      for (hook in private$hooks[[HookEvent$PERMISSION_REQUEST]]) {
        if (!.hook_pattern_matches(hook$pattern, tool_name)) next
        result <- .run_hook_timed(hook$fn, hook$timeout_ms,
                                   tool_name, tool_input, mode)
        if (!is.null(result)) {
          action <- result[["action"]] %||% result
          if (action %in% c("allow", "deny")) return(action)
        }
      }
      NULL
    },

    #' @description Fire UserMessage hooks (informational).
    run_user_message = function(message) {
      for (hook in private$hooks[[HookEvent$USER_MESSAGE]])
        .run_hook_timed(hook$fn, hook$timeout_ms, message)
      invisible(NULL)
    },

    #' @description Fire AssistantMessage hooks (informational).
    run_assistant_message = function(message) {
      for (hook in private$hooks[[HookEvent$ASSISTANT_MESSAGE]])
        .run_hook_timed(hook$fn, hook$timeout_ms, message)
      invisible(NULL)
    },

    #' @description Remove all registered hooks.
    clear = function() {
      for (evt in unlist(HookEvent))
        private$hooks[[evt]] <- list()
      invisible(self)
    },

    #' @description Count total registered hooks across all events.
    count = function() sum(vapply(private$hooks, length, integer(1)))
  )
)

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

.hook_pattern_matches <- function(pattern, tool_name) {
  if (is.null(pattern) || identical(pattern, "*")) return(TRUE)
  if (grepl("*", pattern, fixed = TRUE)) {
    regex <- paste0("^", gsub("*", ".*", pattern, fixed = TRUE), "$")
    return(grepl(regex, tool_name))
  }
  identical(pattern, tool_name)
}

.run_hook_timed <- function(fn, timeout_ms, ...) {
  start  <- proc.time()[["elapsed"]]
  result <- tryCatch(fn(...), error = function(e) {
    warning("[codeagent] Hook error: ", conditionMessage(e), call. = FALSE)
    NULL
  })
  elapsed_ms <- (proc.time()[["elapsed"]] - start) * 1000
  if (elapsed_ms > 500)
    message("[codeagent] Slow hook: ", round(elapsed_ms), "ms")
  if (elapsed_ms > timeout_ms)
    warning("[codeagent] Hook exceeded ", timeout_ms, "ms timeout.", call. = FALSE)
  result
}
