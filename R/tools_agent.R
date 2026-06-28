#' @title Agent Sub-agent Tool
#' @description The Agent tool spawns a sub-agent (a fresh ellmer Chat session)
#'   to handle a delegated task. The sub-agent inherits the parent's tool set
#'   and permission mode but starts with a clean conversation history.
#' @name tools_agent
#' @keywords internal
NULL

# ---------------------------------------------------------------------------
# Agent tool
# ---------------------------------------------------------------------------

#' Create the Agent tool
#'
#' Spawns a sub-agent to handle complex multi-step delegated tasks.
#' The sub-agent runs synchronously and its final response is returned
#' as the tool result.
#'
#' @param model Character. Model for sub-agents.
#' @param mode Character. Permission mode (inherited from parent).
#' @param rules List. Permission rules (inherited).
#' @param max_turns Integer. Max turns for sub-agent (default 30).
#' @return An `ellmer::tool()` object.
#' @export
agent_tool <- function(model       = "claude-sonnet-4-6",
                        mode        = "default",
                        rules       = list(),
                        max_turns   = 30L) {
  ellmer::tool(
    fun = function(description, prompt, subagent_type = NULL) {
      tryCatch({
        # Build sub-agent system prompt
        system_prompt <- paste0(
          "You are a sub-agent helping with: ", description, "\n",
          "Complete the task thoroughly and return your findings/results.\n",
          "You are running in sub-agent mode. Be concise and focused."
        )

        # Create sub-agent chat
        sub_chat <- ellmer::chat_anthropic(
          model         = model,
          system_prompt = system_prompt
        )

        # Register tools for sub-agent (builtin only -- no recursive agent tool)
        register_builtin_tools(sub_chat, mode = mode, rules = rules)

        # Run sub-agent loop (simple, no compaction for sub-agents)
        result <- .run_subagent_loop(sub_chat, prompt, max_turns)
        truncate_tool_result(result, "default")
      }, error = function(e) {
        paste0("[Error] Agent tool failed: ", conditionMessage(e))
      })
    },
    description = paste0(
      "Spawn a sub-agent to handle a complex, multi-step delegated task. ",
      "The sub-agent starts fresh with its own context and returns ",
      "a summary of its findings or results."
    ),
    arguments = list(
      description   = ellmer::type_string(
        "Short description of what the sub-agent will do (3-5 words).",
        required = TRUE),
      prompt        = ellmer::type_string(
        "The full task prompt for the sub-agent.", required = TRUE),
      subagent_type = ellmer::type_string(
        "Optional hint about the type of sub-agent (e.g. 'explore', 'plan').",
        required = FALSE)
    ),
    annotations = ellmer::tool_annotations(
      title            = "Agent",
      read_only_hint   = FALSE,
      destructive_hint = FALSE
    )
  )
}

# ---------------------------------------------------------------------------
# Register agent tool
# ---------------------------------------------------------------------------

#' Register the Agent tool to an ellmer Chat object
#'
#' @param chat An `ellmer::Chat` object.
#' @param model Character. Model for sub-agents.
#' @param mode Character. Permission mode.
#' @param rules List. Permission rules.
#' @param max_turns Integer. Max turns per sub-agent.
#' @return Invisibly returns `chat`.
#' @export
register_agent_tool <- function(chat, model = "claude-sonnet-4-6",
                                  mode = "default", rules = list(),
                                  max_turns = 30L) {
  chat$register_tool(agent_tool(model, mode, rules, max_turns))
  invisible(chat)
}

# ---------------------------------------------------------------------------
# Internal: simple sub-agent loop
# ---------------------------------------------------------------------------

.run_subagent_loop <- function(sub_chat, prompt, max_turns = 30L) {
  # Send initial prompt
  response <- tryCatch(
    sub_chat$chat(prompt),
    error = function(e) paste0("[Error in sub-agent] ", conditionMessage(e))
  )

  # ellmer handles the agentic loop internally when tools are registered
  # and stop_reason != "end_turn". We just return the final text response.
  if (is.character(response)) return(response)
  "[Sub-agent completed with no text output]"
}
