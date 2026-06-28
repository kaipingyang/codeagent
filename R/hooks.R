#' @title Tool Hook System
#' @description Pre- and post-tool execution hooks for codeagent.
#'   Pre-hooks run after permission checks, before execution.
#'   Post-hooks run after execution to inspect or modify output.
#' @name hooks
#' @keywords internal
NULL

# ---------------------------------------------------------------------------
# HookRegistry R6 class
# ---------------------------------------------------------------------------

#' Tool hook registry
#'
#' Manages pre- and post-tool hooks. Each hook is a function that receives
#' tool information and can allow, deny, or modify the operation.
#'
#' ## Pre-hook callback signature
#' `function(tool_name, tool_input)` returning a list with:
#' * `action = "allow"` -- proceed normally
#' * `action = "deny"` -- block execution (with optional `message`)
#' * `action = "updated_input"` -- replace input with `input` field
#'
#' ## Post-hook callback signature
#' `function(tool_name, tool_input, tool_output)` returning a list with:
#' * `action = "allow"` -- pass output through unchanged
#' * `action = "updated_output"` -- replace output with `output` field
#'
#' @export
HookRegistry <- R6::R6Class(
  "HookRegistry",

  private = list(
    pre_hooks  = NULL,   # list of (pattern, fn, timeout_ms)
    post_hooks = NULL    # list of (pattern, fn, timeout_ms)
  ),

  public = list(

    #' @description Create a new registry.
    initialize = function() {
      private$pre_hooks  <- list()
      private$post_hooks <- list()
    },

    #' @description Register a pre-tool hook.
    #' @param fn Function. Pre-hook callback.
    #' @param tool_pattern Character or NULL. Glob-style tool name filter.
    #'   `NULL` matches all tools.
    #' @param timeout_ms Integer. Max milliseconds before warning (default 2000).
    register_pre = function(fn, tool_pattern = NULL, timeout_ms = 2000L) {
      private$pre_hooks <- c(
        private$pre_hooks,
        list(list(pattern = tool_pattern, fn = fn,
                  timeout_ms = as.integer(timeout_ms)))
      )
      invisible(self)
    },

    #' @description Register a post-tool hook.
    #' @param fn Function. Post-hook callback.
    #' @param tool_pattern Character or NULL. Glob-style tool name filter.
    #' @param timeout_ms Integer. Max milliseconds before warning (default 2000).
    register_post = function(fn, tool_pattern = NULL, timeout_ms = 2000L) {
      private$post_hooks <- c(
        private$post_hooks,
        list(list(pattern = tool_pattern, fn = fn,
                  timeout_ms = as.integer(timeout_ms)))
      )
      invisible(self)
    },

    #' @description Run all matching pre-hooks for a tool call.
    #' @param tool_name Character. Tool name.
    #' @param tool_input List. Tool arguments.
    #' @return Named list: `action` ("allow", "deny", "updated_input"),
    #'   optionally `input` and `message`.
    run_pre = function(tool_name, tool_input) {
      current_input <- tool_input
      for (hook in private$pre_hooks) {
        if (!.hook_pattern_matches(hook$pattern, tool_name)) next
        result <- .run_hook_timed(hook$fn, hook$timeout_ms,
                                   tool_name, current_input)
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

    #' @description Run all matching post-hooks for a tool result.
    #' @param tool_name Character. Tool name.
    #' @param tool_input List. Tool arguments (original).
    #' @param tool_output Character. Tool result string.
    #' @return Character. Possibly modified output.
    run_post = function(tool_name, tool_input, tool_output) {
      current_output <- tool_output
      for (hook in private$post_hooks) {
        if (!.hook_pattern_matches(hook$pattern, tool_name)) next
        result <- .run_hook_timed(hook$fn, hook$timeout_ms,
                                   tool_name, tool_input, current_output)
        if (is.null(result)) next
        action <- result[["action"]] %||% "allow"
        if (identical(action, "updated_output") && !is.null(result[["output"]]))
          current_output <- result[["output"]]
      }
      current_output
    },

    #' @description Remove all registered hooks.
    clear = function() {
      private$pre_hooks  <- list()
      private$post_hooks <- list()
      invisible(self)
    }
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

# Run a hook function; warn if slow, return NULL on error
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
    warning("[codeagent] Hook exceeded ", timeout_ms, "ms timeout.",
            call. = FALSE)
  result
}
