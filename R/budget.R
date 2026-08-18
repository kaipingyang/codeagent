#' @title Token Budget Tracker
#' @description BudgetTracker monitors token usage and signals when the agent
#'   should stop. Mirrors Claude Code's budget tracking:
#'   * `.BUDGET_STOP_RATIO` threshold triggers stop
#'   * Diminishing-return detection: stop if token growth < `.BUDGET_MIN_GROWTH`
#'     for `.BUDGET_MAX_STALL_TURNS` consecutive turns
#'   * Minimum `.BUDGET_MIN_ITERATIONS` iterations before stopping
#'   * Optional dollar-cost hard cap (= Claude Code's `maxBudgetUsd`), fires
#'     immediately once actual spend reaches it, independent of the token
#'     heuristics above
#'   * Sub-agents are exempt from budget constraints
#' @name budget
#' @keywords internal
NULL

# Best-effort current spend for `chat`, in US dollars. NA when the Chat has no
# get_cost() method, or when the value it returns is unusable. Note: ellmer's
# get_cost() returns $0 (not NA/error) for a provider/model it has no price
# data for (e.g. an unregistered custom OpenAI-compatible endpoint), which is
# indistinguishable from "really spent $0" -- a dollar-budget cap therefore
# only fires where ellmer actually knows a price for this session's model.
#' @keywords internal
.current_cost_usd <- function(chat) {
  if (is.null(chat) || !("get_cost" %in% names(chat))) return(NA_real_)
  v <- tryCatch(as.numeric(chat$get_cost()), error = function(e) NA_real_)
  if (length(v) != 1L || is.na(v)) NA_real_ else v
}

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
    #' @param current_cost_usd Numeric or NA. Current session spend in US
    #'   dollars (e.g. from [.current_cost_usd()]); NA when unknown/unpriced.
    #' @param max_budget_usd Numeric or NULL. Hard dollar cap; NULL disables
    #'   the check. When set and `current_cost_usd` is known, this fires
    #'   immediately (bypassing `iteration`/`.BUDGET_MIN_ITERATIONS`) -- a
    #'   dollar cap is a hard stop, not a heuristic.
    #' @return Logical. TRUE if the loop should stop.
    should_stop = function(current_tokens, max_tokens,
                           iteration = 1L, is_subagent = FALSE,
                           current_cost_usd = NA_real_, max_budget_usd = NULL) {
      if (isTRUE(is_subagent)) return(FALSE)

      # Dollar-cost hard cap: independent of the iteration/token heuristics
      # below. NA cost (no price data) or NULL cap never trigger this.
      if (!is.null(max_budget_usd) && !is.na(current_cost_usd) &&
          current_cost_usd >= max_budget_usd) return(TRUE)

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
