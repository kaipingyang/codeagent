#' @title Streaming Tool Executor
#' @description Concurrent tool execution scheduler for codeagent.
#'   Concurrent-safe tools run in parallel via promises/futures;
#'   non-concurrent-safe tools run serially (one at a time).
#' @name executor
#' @keywords internal
NULL

# ---------------------------------------------------------------------------
# Concurrent-safety classification
# ---------------------------------------------------------------------------

# Tools that are always safe to run concurrently (read-only or side-effect-free)
.CONCURRENT_SAFE_TOOLS <- c(
  "Read", "Glob", "Grep", "LS",
  "WebFetch", "WebSearch",
  "TaskGet", "TaskList",
  "NotebookRead"
)

# Bash commands that are safe to run concurrently (read-only patterns)
.is_concurrent_safe <- function(tool_name, tool_input = NULL) {
  if (tool_name %in% .CONCURRENT_SAFE_TOOLS) return(TRUE)
  if (identical(tool_name, "Bash") && !is.null(tool_input)) {
    cmd <- tool_input[["command"]] %||% ""
    return(.is_bash_readonly(cmd))
  }
  FALSE
}

# ---------------------------------------------------------------------------
# StreamingToolExecutor R6 class
# ---------------------------------------------------------------------------

#' Concurrent tool execution scheduler
#'
#' Manages parallel execution of concurrent-safe tools while serialising
#' non-concurrent-safe tools. Mirrors Claude Code's `StreamingToolExecutor`.
#'
#' @details
#' Rules:
#' * Concurrent-safe tools run immediately (in parallel with other safe tools).
#' * Non-concurrent-safe tools wait for all running tools to finish,
#'   execute exclusively, then release the queue.
#' * Tool calls submitted while an unsafe tool is running are queued and
#'   executed in order when the unsafe tool completes.
#'
#' @export
StreamingToolExecutor <- R6::R6Class(
  "StreamingToolExecutor",

  private = list(
    # List of pending tool calls (list of lists with name/input/id)
    queue   = NULL,
    # Whether an unsafe tool is currently running
    unsafe_running = FALSE,
    # Accumulated results from all completed calls (list of tool_result lists)
    results = NULL
  ),

  public = list(

    #' @description Create a new executor.
    initialize = function() {
      private$queue   <- list()
      private$results <- list()
    },

    #' @description Submit a tool call for execution.
    #' @param tool_call Named list with `id`, `name`, `input`.
    #' @param exec_fn Function `(tool_call) -> character`. Executes the tool
    #'   and returns the result string.
    #' @return Invisibly NULL (result will appear in `collect_results()`).
    submit = function(tool_call, exec_fn) {
      if (.is_concurrent_safe(tool_call$name, tool_call$input) &&
          !private$unsafe_running) {
        # Run immediately (synchronous path; for async use execute_batch_async())
        result <- tryCatch(
          exec_fn(tool_call),
          error = function(e) paste0("[Error] ", conditionMessage(e))
        )
        private$results <- c(private$results,
                             list(list(id = tool_call$id,
                                       name = tool_call$name,
                                       result = result)))
      } else {
        # Queue for serial execution
        private$queue <- c(private$queue, list(
          list(call = tool_call, exec_fn = exec_fn)
        ))
      }
      invisible(NULL)
    },

    #' @description Drain the queue for any unsafe tool that was running.
    #'   Call this after marking the unsafe tool as complete.
    #' @param exec_fn Function `(tool_call) -> character`. Executor function.
    drain_queue = function() {
      while (length(private$queue) > 0L) {
        item   <- private$queue[[1L]]
        private$queue <- private$queue[-1L]

        is_safe <- .is_concurrent_safe(item$call$name, item$call$input)
        private$unsafe_running <- !is_safe

        result <- tryCatch(
          item$exec_fn(item$call),
          error = function(e) paste0("[Error] ", conditionMessage(e))
        )
        private$results <- c(private$results,
                             list(list(id     = item$call$id,
                                       name   = item$call$name,
                                       result = result)))

        # If this was an unsafe tool, run any following safe tools first
        if (!is_safe) {
          private$unsafe_running <- FALSE
          # Continue loop to drain safe tools that may follow
        }
      }
      invisible(NULL)
    },

    #' @description Collect all completed results and reset the accumulator.
    #' @return List of result objects (each with `id`, `name`, `result`).
    collect_results = function() {
      res              <- private$results
      private$results  <- list()
      res
    },

    #' @description Execute a batch of tool calls, respecting concurrency rules.
    #' @param tool_calls List of tool call objects.
    #' @param exec_fn Function `(tool_call) -> character`.
    #' @return List of result objects.
    execute_batch = function(tool_calls, exec_fn) {
      private$results <- list()

      for (tc in tool_calls) {
        self$submit(tc, exec_fn)
      }
      self$drain_queue()
      self$collect_results()
    },

    #' @description Async variant of `execute_batch()` for use inside
    #'   `coro::async` / Shiny `ExtendedTask` contexts.
    #'
    #'   Concurrent-safe tools are dispatched as a group via
    #'   `promises::promise_all()`, so the Shiny event loop can interleave
    #'   other work while they run.  Unsafe tools execute serially after all
    #'   safe tools have resolved.
    #'
    #'   If the `promises` package is not installed the method falls back to
    #'   `execute_batch()` and returns the result directly (not wrapped in a
    #'   promise); `coro::await()` handles plain values transparently.
    #'
    #' @param tool_calls List of tool call objects (each with `id`, `name`,
    #'   `input`).
    #' @param exec_fn Function `(tool_call) -> character`.  Must be callable
    #'   from the current R process.
    #' @return A `promises::promise` resolving to the same list that
    #'   `execute_batch()` returns, or that list directly when `promises` is
    #'   unavailable.
    execute_batch_async = function(tool_calls, exec_fn) {
      if (!requireNamespace("promises", quietly = TRUE))
        return(self$execute_batch(tool_calls, exec_fn))

      safe_calls   <- Filter(
        function(tc) .is_concurrent_safe(tc$name, tc$input), tool_calls)
      unsafe_calls <- Filter(
        function(tc) !.is_concurrent_safe(tc$name, tc$input), tool_calls)

      # Wrap a single tool call as a promise resolving to a result list entry
      .as_promise <- function(tc) {
        promises::then(
          promises::promise(function(resolve, reject) {
            resolve(tryCatch(
              exec_fn(tc),
              error = function(e) paste0("[Error] ", conditionMessage(e))
            ))
          }),
          function(result) list(id = tc$id, name = tc$name, result = result)
        )
      }

      # Dispatch all concurrent-safe tools at once; chain unsafe tools after
      safe_p <- if (length(safe_calls) > 0L)
        promises::promise_all(.list = lapply(safe_calls, .as_promise))
      else
        promises::promise_resolve(list())

      promises::then(safe_p, function(safe_res) {
        results <- unname(safe_res)
        for (tc in unsafe_calls) {
          result  <- tryCatch(
            exec_fn(tc),
            error = function(e) paste0("[Error] ", conditionMessage(e))
          )
          results <- c(results, list(list(id = tc$id, name = tc$name,
                                          result = result)))
        }
        results
      })
    }
  )
)
