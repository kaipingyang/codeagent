#' @title Type Constructors
#' @description Lightweight S3 constructors for codeagent's type system.
#'   Adapted from ClaudeAgentSDK. All objects are named lists with a
#'   `class` attribute.
#' @name types
#' @keywords internal
NULL

# ---------------------------------------------------------------------------
# Helper
# ---------------------------------------------------------------------------

.new_obj <- function(fields, class) {
  structure(fields, class = c(class, "list"))
}

# ---------------------------------------------------------------------------
# Content block types
# ---------------------------------------------------------------------------

#' Create a TextBlock
#' @param text Character. The text content.
#' @return Object of class `TextBlock`.
#' @export
TextBlock <- function(text) {
  .new_obj(list(text = text), "TextBlock")
}

#' Create a ThinkingBlock
#' @param thinking Character. The thinking content.
#' @param signature Character. Signature for extended thinking.
#' @return Object of class `ThinkingBlock`.
#' @export
ThinkingBlock <- function(thinking, signature = "") {
  .new_obj(list(thinking = thinking, signature = signature), "ThinkingBlock")
}

#' Create a ToolUseBlock
#' @param id Character. Tool use ID.
#' @param name Character. Tool name.
#' @param input List. Tool input parameters.
#' @return Object of class `ToolUseBlock`.
#' @export
ToolUseBlock <- function(id, name, input) {
  .new_obj(list(id = id, name = name, input = input), "ToolUseBlock")
}

#' Create a ToolResultBlock
#' @param tool_use_id Character. ID of the corresponding tool use.
#' @param content Character, list, or NULL. Tool result content.
#' @param is_error Logical or NULL. Whether this is an error result.
#' @return Object of class `ToolResultBlock`.
#' @export
ToolResultBlock <- function(tool_use_id, content = NULL, is_error = NULL) {
  .new_obj(
    list(tool_use_id = tool_use_id, content = content, is_error = is_error),
    "ToolResultBlock"
  )
}

# ---------------------------------------------------------------------------
# Permission types
# ---------------------------------------------------------------------------

#' Allow a tool call
#' @param updated_input List or NULL. Modified tool input (if any).
#' @return Object of class `PermissionResultAllow`.
#' @export
PermissionResultAllow <- function(updated_input = NULL) {
  .new_obj(list(behavior = "allow", updated_input = updated_input),
           "PermissionResultAllow")
}

#' Deny a tool call
#' @param message Character. Reason for denial.
#' @param interrupt Logical. Whether to interrupt the agent.
#' @return Object of class `PermissionResultDeny`.
#' @export
PermissionResultDeny <- function(message = "", interrupt = FALSE) {
  .new_obj(list(behavior = "deny", message = message, interrupt = interrupt),
           "PermissionResultDeny")
}

#' Create a permission rule
#' @param tool_name Character. Tool name pattern (supports `*` wildcard).
#' @param behavior Character. One of `"allow"`, `"deny"`, `"ask"`.
#' @param source Character. Rule source for priority ordering.
#' @param rule_content Character or NULL. Fine-grained condition (e.g. `"npm test:*"`).
#' @return Object of class `PermissionRule`.
#' @export
PermissionRule <- function(tool_name, behavior = c("allow", "deny", "ask"),
                            source = "session",
                            rule_content = NULL) {
  behavior <- match.arg(behavior)
  .new_obj(
    list(tool_name = tool_name, behavior = behavior,
         source = source, rule_content = rule_content),
    "PermissionRule"
  )
}

# ---------------------------------------------------------------------------
# Skill types
# ---------------------------------------------------------------------------

#' Skill metadata (frontmatter-only, no full content)
#' @param name Character. Skill name.
#' @param description Character. One-line description shown in skill list.
#' @param argument_hint Character. Hint shown after skill name (e.g. "<task>").
#' @param auto_trigger Logical. Whether LLM may auto-invoke this skill.
#' @param allowed_tools Character vector or NULL. Tools this skill may use.
#' @param base_dir Character. Directory containing SKILL.md.
#' @param path Character. Absolute path to SKILL.md.
#' @return Object of class `SkillMeta`.
#' @keywords internal
SkillMeta <- function(name, description = "", argument_hint = "",
                       auto_trigger = TRUE, allowed_tools = NULL,
                       base_dir = NULL, path = NULL) {
  .new_obj(
    list(name = name, description = description,
         argument_hint = argument_hint, auto_trigger = auto_trigger,
         allowed_tools = allowed_tools, base_dir = base_dir, path = path),
    "SkillMeta"
  )
}

# ---------------------------------------------------------------------------
# Hook types
# ---------------------------------------------------------------------------

#' Pre-tool hook definition
#' @param fn Function. `function(tool_name, tool_input)` -> list with
#'   `action` (`"allow"`, `"deny"`, `"updated_input"`) and optional fields.
#' @param tool_pattern Character or NULL. Regex pattern to match tool names.
#'   `NULL` matches all tools.
#' @param timeout_ms Integer. Timeout in milliseconds (default 2000).
#' @return Object of class `PreToolHook`.
#' @export
PreToolHook <- function(fn, tool_pattern = NULL, timeout_ms = 2000L) {
  .new_obj(list(fn = fn, tool_pattern = tool_pattern, timeout_ms = timeout_ms),
           "PreToolHook")
}

#' Post-tool hook definition
#' @param fn Function. `function(tool_name, tool_input, tool_output)` -> list
#'   with `action` (`"allow"`, `"updated_output"`) and optional fields.
#' @param tool_pattern Character or NULL. Regex pattern to match tool names.
#' @param timeout_ms Integer. Timeout in milliseconds (default 2000).
#' @return Object of class `PostToolHook`.
#' @export
PostToolHook <- function(fn, tool_pattern = NULL, timeout_ms = 2000L) {
  .new_obj(list(fn = fn, tool_pattern = tool_pattern, timeout_ms = timeout_ms),
           "PostToolHook")
}

# ---------------------------------------------------------------------------
# Session info / message types (for session list/management)
# ---------------------------------------------------------------------------

#' Session message object (for display/export)
#' @param type Character. "user" or "assistant".
#' @param role Character. Alias for type.
#' @param text Character. Message text.
#' @param uuid Character. Message UUID.
#' @param session_id Character. Session UUID.
#' @return Object of class `SessionMessage`.
#' @keywords internal
SessionMessage <- function(type = "user", role = NULL,
                            text = "", uuid = "",
                            session_id = "") {
  .new_obj(
    list(type = type, role = role %||% type, text = text,
         uuid = uuid, session_id = session_id),
    "SessionMessage"
  )
}

# ---------------------------------------------------------------------------
# Session info type (for session list/management)
# ---------------------------------------------------------------------------

#' Session info object
#' @param session_id Character. UUID.
#' @param summary Character. Short summary.
#' @param last_modified Numeric. mtime in ms.
#' @param file_size Numeric or NULL. File size in bytes.
#' @param custom_title Character or NULL.
#' @param first_prompt Character or NULL.
#' @param git_branch Character or NULL.
#' @param cwd Character or NULL.
#' @param tag Character or NULL.
#' @param created_at Numeric or NULL. Creation timestamp in ms.
#' @return Object of class `SessionInfo`.
#' @keywords internal
SessionInfo <- function(session_id, summary, last_modified,
                         file_size = NULL, custom_title = NULL,
                         first_prompt = NULL, git_branch = NULL,
                         cwd = NULL, tag = NULL, created_at = NULL) {
  .new_obj(
    list(session_id = session_id, summary = summary,
         last_modified = last_modified, file_size = file_size,
         custom_title = custom_title, first_prompt = first_prompt,
         git_branch = git_branch, cwd = cwd, tag = tag,
         created_at = created_at),
    "SessionInfo"
  )
}
