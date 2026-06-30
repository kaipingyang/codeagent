#' @title Plan Mode Tools
#' @description Tools that let the model enter and exit a read-only planning
#'   mode mid-conversation, mirroring Claude Code's EnterPlanMode/ExitPlanMode.
#'   They flip a shared `mode_env$mode` slot that every permission checker reads
#'   live (see `.make_permission_checker()` in `tools_builtin.R`), so switching
#'   to `"plan"` immediately makes all write/exec tools deny while reads still
#'   pass.
#' @name tools_plan
#' @keywords internal
NULL

#' Create the EnterPlanMode tool
#'
#' @param mode_env Environment with a `$mode` slot (the live permission mode).
#' @return An `ellmer::tool()` object.
#' @keywords internal
enter_plan_mode_tool <- function(mode_env) {
  force(mode_env)
  ellmer::tool(
    fun = function(reason = NULL) {
      prev <- mode_env$mode %||% "default"
      mode_env$prev <- prev
      mode_env$mode <- "plan"
      msg <- paste0(
        "Entered plan mode (read-only). Write, edit, and shell tools are now ",
        "blocked; only read/search tools work. Call exit_plan_mode when the ",
        "plan is ready.",
        if (!is.null(reason) && nzchar(reason)) paste0("\nReason: ", reason) else ""
      )
      .tool_result2(msg, kind = "text", icon = "clipboard",
                    title = "Plan mode: ON",
                    payload = list(text = msg))
    },
    description = paste0(
      "Enter read-only plan mode. Use this before making changes to think ",
      "through an approach: all write/edit/shell tools are blocked until you ",
      "call exit_plan_mode, but you can still read and search."
    ),
    arguments = list(
      reason = ellmer::type_string(
        "Optional short note on why you are entering plan mode.",
        required = FALSE)
    ),
    annotations = ellmer::tool_annotations(
      title = "EnterPlanMode", read_only_hint = TRUE, open_world_hint = FALSE)
  )
}

#' Create the ExitPlanMode tool
#'
#' @param mode_env Environment with a `$mode` slot (the live permission mode).
#' @return An `ellmer::tool()` object.
#' @keywords internal
exit_plan_mode_tool <- function(mode_env) {
  force(mode_env)
  ellmer::tool(
    fun = function() {
      restored <- mode_env$prev %||% "default"
      # Never restore back into "plan" (would be a no-op trap).
      if (identical(restored, "plan")) restored <- "default"
      mode_env$mode <- restored
      msg <- paste0("Exited plan mode. Permission mode restored to '",
                    restored, "'. Write/edit/shell tools are available again.")
      .tool_result2(msg, kind = "text", icon = "check",
                    title = "Plan mode: OFF",
                    payload = list(text = msg))
    },
    description = paste0(
      "Exit read-only plan mode and restore the previous permission mode so ",
      "you can apply changes. Call this once your plan is ready."
    ),
    arguments = list(),
    annotations = ellmer::tool_annotations(
      title = "ExitPlanMode", read_only_hint = TRUE, open_world_hint = FALSE)
  )
}

#' Register the plan-mode tools on a chat
#'
#' @param chat An `ellmer::Chat` object.
#' @param mode_env Environment with a live `$mode` slot.
#' @return Invisibly `chat`.
#' @keywords internal
register_plan_mode_tools <- function(chat, mode_env) {
  chat$register_tool(enter_plan_mode_tool(mode_env))
  chat$register_tool(exit_plan_mode_tool(mode_env))
  invisible(chat)
}
