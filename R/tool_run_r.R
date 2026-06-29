#' @title Run R Code Tool (permission-gated)
#' @description Wraps [btw::btw_tool_run_r()] behind codeagent's permission gate.
#'   Executing arbitrary R code is dangerous (no sandbox, runs in the global
#'   environment), so this tool is treated like Bash: `destructive_hint = TRUE`,
#'   never read-only, and every call must be confirmed via `ask_fn` in `default`
#'   mode (or a permission rule / `bypass`).
#' @name tool_run_r
#' @keywords internal
NULL

#' Create the RunR tool
#'
#' Runs R code in the current session and captures return values, printed
#' output, messages, warnings, errors, and plots. Because arbitrary R execution
#' can read/write files, hit the network, or mutate global state, the call is
#' gated through [check_permission()] under the tool name `"RunR"`.
#'
#' @param mode Character. Permission mode (see [PermissionMode]).
#' @param rules List. [PermissionRule()] objects.
#' @param ask_fn Function or NULL. `function(tool_name, input) -> logical`.
#'   Called when permission resolves to `"ask"`.
#' @return An `ellmer::tool()` object, or `NULL` if btw is unavailable.
#' @export
run_r_tool <- function(mode = "default", rules = list(), ask_fn = NULL) {
  if (!requireNamespace("btw", quietly = TRUE)) {
    warning("[codeagent] btw not available; RunR tool skipped.", call. = FALSE)
    return(NULL)
  }
  checker <- .make_permission_checker("RunR", mode, rules, ask_fn)

  ellmer::tool(
    fun = function(code, `_intent` = NULL) {
      if (!checker(list(code = code))) {
        return(.tool_result(
          paste0("[Permission denied] RunR:\n", code),
          title = "RunR — denied"
        ))
      }
      tryCatch(
        # btw_tool_run_r returns a list of ellmer Content objects (text,
        # messages, warnings, errors, inline plots). Return it directly so
        # shinychat renders plots and structured output.
        btw::btw_tool_run_r(code = code, `_intent` = `_intent` %||% ""),
        error = function(e) {
          .tool_result(paste0("[Error] ", conditionMessage(e)),
                       title = "RunR — error")
        }
      )
    },
    name = "RunR",
    description = paste0(
      "Execute R code in the current R session and capture return values, ",
      "printed output, messages, warnings, errors, and plots. Execution stops ",
      "at the first error. Use for data inspection, quick computations, ",
      "plotting, and exercising package functions. ",
      "DANGER: code runs unsandboxed in the global environment and can read or ",
      "write files, access the network, and mutate state — every call is ",
      "permission-gated and may require user confirmation."
    ),
    arguments = list(
      code = ellmer::type_string(
        "The R code to run.", required = TRUE),
      `_intent` = ellmer::type_string(
        "Brief description of why this code is being run.", required = FALSE)
    ),
    annotations = ellmer::tool_annotations(
      title            = "Run R code",
      read_only_hint   = FALSE,
      destructive_hint = TRUE,
      open_world_hint  = TRUE
    )
  )
}

#' Register the RunR tool to a Chat
#'
#' @inheritParams run_r_tool
#' @param chat An `ellmer::Chat` object.
#' @return Invisibly returns `chat`.
#' @keywords internal
register_run_r_tool <- function(chat, mode = "default", rules = list(),
                                ask_fn = NULL) {
  t <- run_r_tool(mode, rules, ask_fn)
  if (!is.null(t)) chat$register_tool(t)
  invisible(chat)
}
