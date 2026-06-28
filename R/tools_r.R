#' @title R Environment Tools
#' @description Integration with the btw package for R-environment tools:
#'   data frame inspection, package docs, session info, git, search, web fetch.
#'   All tools are `ellmer::tool()` objects sourced from `btw::btw_tools()`.
#' @name tools_r
#' @keywords internal
NULL

# Tool-name prefixes that map to logical groups (for optional filtering)
.BTW_GROUPS <- list(
  env     = "btw_tool_env_",
  docs    = "btw_tool_docs_",
  files   = "btw_tool_files_",
  git     = "btw_tool_git_",
  search  = "btw_tool_search_",
  session = "btw_tool_session_",
  web     = "btw_tool_web_"
)

#' Register btw R-environment tools to an ellmer Chat object
#'
#' Wraps [btw::btw_tools()] and registers each returned tool to `chat`.
#' If `btw` is not installed a warning is emitted and nothing is registered.
#'
#' @param chat An `ellmer::Chat` object.
#' @param groups Character vector of group names to include, or `NULL` for all.
#'   Valid groups: `"env"`, `"docs"`, `"files"`, `"git"`, `"search"`,
#'   `"session"`, `"web"`.
#' @return Invisibly returns the number of tools registered.
#' @export
register_r_tools <- function(chat, groups = NULL) {
  if (!requireNamespace("btw", quietly = TRUE)) {
    warning("[codeagent] btw package not available; R-environment tools skipped.",
            call. = FALSE)
    return(invisible(0L))
  }

  all_tools <- btw::btw_tools()

  # Filter by group if requested
  if (!is.null(groups)) {
    valid_groups   <- names(.BTW_GROUPS)
    unknown_groups <- setdiff(groups, valid_groups)
    if (length(unknown_groups) > 0L) {
      warning(
        "[codeagent] Unknown btw tool group(s): ",
        paste(unknown_groups, collapse = ", "),
        ". Valid groups: ",
        paste(sort(valid_groups), collapse = ", "),
        ".",
        call. = FALSE
      )
    }
    known_groups <- intersect(groups, valid_groups)
    if (length(known_groups) == 0L) return(invisible(0L))
    prefixes <- unlist(.BTW_GROUPS[known_groups])
    if (length(prefixes) > 0L) {
      all_tools <- Filter(function(t) {
        any(vapply(prefixes, function(p)
          startsWith(t@name, p), logical(1L)))
      }, all_tools)
    }
  }

  for (tool in all_tools) {
    chat$register_tool(tool)
  }
  invisible(length(all_tools))
}
