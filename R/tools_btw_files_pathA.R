#' @title Path A -- btw File Tools with Permission Gate (EXPERIMENTAL)
#' @description Wraps btw's file tools (files_read, files_write, files_edit,
#'   files_replace, files_list, files_search) with codeagent's permission
#'   system, replacing codeagent's own Read/Write/Edit/Glob/Grep/LS tools.
#'
#'   **Not loaded by default.** Opt in:
#'   ```r
#'   source(system.file("pathA/tools_btw_files.R", package = "codeagent"))
#'   client <- codeagent_client(chat, use_btw_files = TRUE)
#'   ```
#'
#'   Benefits over codeagent's own file tools:
#'   - btw `files_edit`: hashline-anchored edits reject stale changes
#'   - btw `files_read`: returns hashline annotations for precise editing
#'   - Unified permission gate on all write operations
#'
#'   Limitation: btw tools enforce paths relative to cwd; absolute paths
#'   outside cwd are rejected by btw's `check_path_within_current_wd()`.
#'
#' @name tools_btw_files_pathA
#' @keywords internal
NULL

# ---------------------------------------------------------------------------
# Core: wrap a btw ToolDef with a permission checker
# ---------------------------------------------------------------------------

#' Wrap a btw ToolDef with codeagent's permission gate
#'
#' Uses `S7::S7_data()` to extract the underlying R function from a btw
#' `ToolDef` S7 object, wraps it with a permission checker, then rebuilds
#' a new `ellmer::tool()` preserving the original description, arguments,
#' and annotations.
#'
#' @param btw_tool An `ellmer::ToolDef` from `btw::btw_tools()`.
#' @param mode Character. Permission mode.
#' @param rules List. Permission rules.
#' @param ask_fn Function or NULL. Interactive ask callback.
#' @return A new `ellmer::ToolDef` with permission gate injected.
#' @keywords internal
.wrap_btw_tool_permission <- function(btw_tool, mode = "default",
                                       rules = list(), ask_fn = NULL) {
  original_fn <- tryCatch(S7::S7_data(btw_tool),
                           error = function(e) NULL)
  if (!is.function(original_fn))
    stop("Cannot extract function from btw tool: ", btw_tool@name, call. = FALSE)

  checker <- .make_permission_checker(btw_tool@name, mode, rules, ask_fn)
  force(checker)
  force(original_fn)
  tool_name <- btw_tool@name

  # Rebuild tool() with permission gate prepended
  # We use ... to pass all arguments through to original_fn transparently
  ellmer::tool(
    fun = function(...) {
      args <- list(...)
      # _intent is purely display -- never pass to underlying fn for permission check
      check_args <- args[names(args) != "_intent"]
      if (!checker(check_args))
        return(ellmer::ContentToolResult(
          value = paste0("[Permission denied] ", tool_name),
          extra = list(display = list(
            title = htmltools::HTML(sprintf(
              "<code>%s</code> -- permission denied (%s mode)",
              htmltools::htmlEscape(tool_name), mode
            ))
          ))
        ))
      do.call(original_fn, args)
    },
    description = btw_tool@description,
    arguments   = btw_tool@arguments@properties,
    annotations = btw_tool@annotations
  )
}

# ---------------------------------------------------------------------------
# Register btw file tools with permission gate
# ---------------------------------------------------------------------------

# Read-only btw file tools (no permission gate needed beyond readonly check)
.BTW_FILE_READONLY <- c(
  "btw_tool_files_read",
  "btw_tool_files_list",
  "btw_tool_files_search"
)

# Write btw file tools (need permission gate)
.BTW_FILE_WRITE <- c(
  "btw_tool_files_write",
  "btw_tool_files_edit",
  "btw_tool_files_replace"
)

#' Register btw file tools with permission control
#'
#' Replaces codeagent's built-in Read/Write/Edit/Glob/Grep/LS tools with
#' btw's superior equivalents. Write tools get the permission gate; read
#' tools are registered directly.
#'
#' **Experimental -- not loaded by default.**
#'
#' @param chat An `ellmer::Chat` object.
#' @param mode Character. Permission mode.
#' @param rules List. Permission rules.
#' @param ask_fn Function or NULL.
#' @return Invisibly returns the number of tools registered.
#' @export
register_btw_file_tools <- function(chat, mode = "default",
                                     rules = list(), ask_fn = NULL) {
  if (!requireNamespace("btw", quietly = TRUE)) {
    warning("[codeagent] btw required for register_btw_file_tools().", call. = FALSE)
    return(invisible(0L))
  }

  all_file_tools <- btw::btw_tools("files")
  registered <- 0L

  for (t in all_file_tools) {
    if (t@name %in% .BTW_FILE_WRITE) {
      # Wrap write tools with permission gate
      wrapped <- tryCatch(
        .wrap_btw_tool_permission(t, mode, rules, ask_fn),
        error = function(e) {
          warning("[codeagent] Could not wrap ", t@name, ": ", conditionMessage(e),
                  call. = FALSE)
          NULL
        }
      )
      if (!is.null(wrapped)) {
        chat$register_tool(wrapped)
        registered <- registered + 1L
      }
    } else {
      # Read-only: register directly
      chat$register_tool(t)
      registered <- registered + 1L
    }
  }

  message(sprintf("[codeagent] Path A: registered %d btw file tools (mode: %s)",
                  registered, mode))
  invisible(registered)
}

# ---------------------------------------------------------------------------
# codeagent_client() integration (opt-in via use_btw_files = TRUE)
# ---------------------------------------------------------------------------

#' Patch codeagent_client() to use btw file tools (Path A)
#'
#' Call this once after loading codeagent to enable btw file tools globally.
#' Modifies `.register_all_tools()` behaviour for subsequent `codeagent_client()` calls.
#'
#' ```r
#' library(codeagent)
#' source(system.file("pathA/tools_btw_files.R", package = "codeagent"))
#' enable_btw_file_tools()   # opt in
#' client <- codeagent_client(chat)
#' ```
#' @export
enable_btw_file_tools <- function() {
  options(codeagent.use_btw_files = TRUE)
  message("[codeagent] Path A enabled: btw file tools will be used in future codeagent_client() calls.")
  invisible(NULL)
}
