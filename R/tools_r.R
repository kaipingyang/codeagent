#' @title R Environment Tools
#' @description Integration with the btw package for R-environment tools:
#'   data frame inspection, package docs, session info, git, search, web fetch,
#'   package development (pkg), CRAN search (cran), IDE integration, and
#'   sub-agent delegation (agent).
#'   All tools are `ellmer::tool()` objects sourced from `btw::btw_tools()`.
#' @name tools_r
#' @keywords internal
NULL

# Tool-name prefixes that map to logical groups (for optional filtering).
# Covers all groups available in btw 1.2.1.
.BTW_GROUPS <- list(
  agent       = "btw_tool_agent_",
  cran        = "btw_tool_cran_",
  docs        = "btw_tool_docs_",
  env         = "btw_tool_env_",
  files       = "btw_tool_files_",
  git         = "btw_tool_git_",
  github      = "btw_tool_github",
  ide         = "btw_tool_ide_",
  pkg         = "btw_tool_pkg_",
  sessioninfo = "btw_tool_sessioninfo_",
  web         = "btw_tool_web_"
  # "skill" group (btw_tool_skill) is registered separately via .make_skill_tool()
)

#' Register btw R-environment tools to an ellmer Chat object
#'
#' Wraps [btw::btw_tools()] and registers each returned tool to `chat`.
#' If `btw` is not installed a warning is emitted and nothing is registered.
#'
#' The `files` group (`btw_tool_files_*`) is included by default and provides
#' hashline-validated precise editing -- superior to codeagent's own file tools
#' for read/write/edit operations. codeagent's built-in tools remain for
#' permission-gated Bash and legacy compatibility.
#'
#' The `skill` group is intentionally excluded here; it is registered via
#' [codeagent_client()] using `.make_skill_tool()` which merges btw skills
#' with codeagent's own skill discovery.
#'
#' @param chat An `ellmer::Chat` object.
#' @param groups Character vector of group names to include, or `NULL` for all.
#'   Valid groups: `"agent"`, `"cran"`, `"docs"`, `"env"`, `"files"`,
#'   `"git"`, `"github"`, `"ide"`, `"pkg"`, `"sessioninfo"`, `"web"`.
#'   `"files"` is included in the default `NULL` (all groups).
#' @return Invisibly returns the number of tools registered.
#' @export
register_r_tools <- function(chat, groups = NULL) {
  if (!requireNamespace("btw", quietly = TRUE)) {
    warning("[codeagent] btw package not available; R-environment tools skipped.",
            call. = FALSE)
    return(invisible(0L))
  }

  all_tools <- btw::btw_tools()

  # Always exclude btw_tool_skill -- handled by codeagent's skill system
  all_tools <- Filter(function(t) !identical(t@name, "btw_tool_skill"), all_tools)

  # Always exclude the 'files' group here -- file tools are owned by the
  # file_tools setting (codeagent core tools and/or register_btw_file_tools /
  # Path A). This prevents the double-registration where btw file tools also
  # arrived (previously ungated) via the default all-groups path.
  all_tools <- Filter(function(t) !startsWith(t@name, "btw_tool_files_"), all_tools)

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

#' R package test verification function
#'
#' Runs `devtools::test()` and returns pass/fail. Use as `verify_fn` in
#' [codeagent_client()] to automatically re-prompt when tests fail.
#'
#' @return A function suitable for `verify_fn`.
#' @export
verify_r_tests <- function() {
  function(response, chat, cwd) {
    if (!requireNamespace("devtools", quietly = TRUE))
      return(list(passed = TRUE))
    result <- tryCatch({
      withr::with_dir(cwd, {
        res <- devtools::test(reporter = "silent")
        failures <- sum(vapply(res, function(r) r$failed + r$error, integer(1)))
        list(
          passed  = failures == 0L,
          message = if (failures > 0L)
            sprintf("%d test(s) failed. Run devtools::test() for details.", failures)
          else ""
        )
      })
    }, error = function(e) {
      list(passed = FALSE, message = conditionMessage(e))
    })
    result
  }
}
