#' @title Token Budget Tracker
#' @description BudgetTracker monitors token usage and signals when the agent
#'   should stop. Mirrors Claude Code's budget tracking:
#'   * `.BUDGET_STOP_RATIO` threshold triggers stop
#'   * Diminishing-return detection: stop if token growth < `.BUDGET_MIN_GROWTH`
#'     for `.BUDGET_MAX_STALL_TURNS` consecutive turns
#'   * Minimum `.BUDGET_MIN_ITERATIONS` iterations before stopping
#'   * Sub-agents are exempt from budget constraints
#' @name budget
#' @keywords internal
NULL

# ---------------------------------------------------------------------------
# BudgetTracker R6 class
# ---------------------------------------------------------------------------

#' Token budget tracker
#'
#' Monitors token consumption and detects when the agent loop should stop
#' due to context exhaustion or diminishing returns.
#'
#' @export
BudgetTracker <- R6::R6Class(
  "BudgetTracker",

  private = list(
    prev_tokens  = 0L,
    same_count   = 0L   # consecutive turns with < .BUDGET_MIN_GROWTH token growth
  ),

  public = list(

    #' @description Reset the tracker state.
    reset = function() {
      private$prev_tokens <- 0L
      private$same_count  <- 0L
      invisible(self)
    },

    #' @description Determine whether the agent loop should stop.
    #' @param current_tokens Integer. Current total token count.
    #' @param max_tokens Integer. Maximum allowed tokens (model context limit).
    #' @param iteration Integer. Current loop iteration (1-indexed).
    #' @param is_subagent Logical. If TRUE, budget limits are not applied.
    #' @return Logical. TRUE if the loop should stop.
    should_stop = function(current_tokens, max_tokens,
                           iteration = 1L, is_subagent = FALSE) {
      if (isTRUE(is_subagent)) return(FALSE)
      if (iteration < .BUDGET_MIN_ITERATIONS) return(FALSE)

      # Hard stop at budget ratio threshold
      if (current_tokens >= max_tokens * .BUDGET_STOP_RATIO) return(TRUE)

      # Diminishing-return detection: < min growth for max stall turns
      delta <- current_tokens - private$prev_tokens
      if (delta < .BUDGET_MIN_GROWTH) {
        private$same_count <- private$same_count + 1L
        if (private$same_count >= .BUDGET_MAX_STALL_TURNS) return(TRUE)
      } else {
        private$same_count <- 0L
      }
      private$prev_tokens <- current_tokens
      FALSE
    },

    #' @description Return current tracker state.
    #' @return Named list with `prev_tokens` and `same_count`.
    state = function() {
      list(prev_tokens = private$prev_tokens,
           same_count  = private$same_count)
    }
  )
)
