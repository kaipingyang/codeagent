#' @title Path A -- btw File Tools with Permission Gate (EXPERIMENTAL)
#' @description Wraps btw's file tools with codeagent's permission system.
#'
#'   **Design rationale -- two parallel edit paths:**
#'
#'   | Path | Tools | Scope | Strength |
#'   |------|-------|-------|----------|
#'   | **Default** (codeagent) | Read/Write/Edit/MultiEdit/Glob/Grep/LS | Any absolute path | Full filesystem access |
#'   | **Path A** (btw, this file) | files_read/write/edit/replace/patch/list/search | Project cwd only | Hash-anchored edits, atomic patch |
#'
#'   The cwd restriction in Path A is **intentional and desirable** for
#'   security-conscious environments: the agent cannot accidentally (or
#'   maliciously) modify files outside the project directory. The default path
#'   is more powerful but riskier; use it when you need to read system paths,
#'   other projects, `/tmp`, etc.
#'
#'   Use both: Path A is opt-in via `enable_btw_file_tools()`, and
#'   coexists with the default tools. The LLM chooses the right tool for each
#'   task: btw tools for project-local edits (safer, hash-verified), default
#'   tools for absolute paths.
#'
#'   **Not loaded by default.** Opt in with:
#'   ```r
#'   enable_btw_file_tools()          # sets options(codeagent.use_btw_files = TRUE)
#'   client <- codeagent_client(chat) # both tool sets registered
#'   ```
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

  # Rebuild tool() with the permission gate prepended. ellmer validates that
  # `arguments` match the fn's formals, so we cannot use `function(...)` -- we
  # copy the original fn's formals via rlang::new_function (same technique as
  # .asyncify_gated_tool). `_intent` is display-only and excluded from the
  # permission check but still forwarded to the underlying fn.
  body_expr <- quote({
    .args       <- as.list(environment())
    .check_args <- .args[names(.args) != "_intent"]
    if (!checker(.check_args)) {
      return(ellmer::ContentToolResult(
        value = paste0("[Permission denied] ", tool_name),
        extra = list(display = list(
          title = htmltools::HTML(sprintf(
            "<code>%s</code> -- permission denied (%s mode)",
            htmltools::htmlEscape(tool_name), mode
          ))
        ))
      ))
    }
    do.call(original_fn, .args)
  })
  wrapped_fun <- rlang::new_function(formals(original_fn), body_expr,
                                     env = environment())

  ellmer::tool(
    fun         = wrapped_fun,
    name        = tool_name,
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
  "btw_tool_files_replace",
  "btw_tool_files_patch"   # atomic multi-file patch (btw >= 1.3.0)
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
