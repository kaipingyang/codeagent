#' @title btw task reuse (skill / README / project-context creation)
#' @description codeagent reuses btw's task + agent helpers instead of
#'   reinventing them. btw exposes each task in several modes; `mode = "tool"`
#'   returns an `ellmer::tool()` the agent can call, `mode = "console"` runs an
#'   interactive guided task. See `btw::btw_task*`.
#' @name tasks_btw
#' @keywords internal
NULL

# Extract the underlying ellmer Chat from a codeagent client OR pass a Chat
# through unchanged.
.as_ellmer_chat <- function(client = NULL) {
  if (is.null(client)) return(NULL)
  if (inherits(client, "Chat")) return(client)
  ch <- tryCatch(client$chat, error = function(e) NULL)
  if (inherits(ch, "Chat")) return(ch)
  NULL
}

# Opt-in: register btw's task helpers as LLM tools (mode = "tool"). Enabled by
# settings$btw_tasks (default FALSE) or options(codeagent.btw_tasks = TRUE).
# No-op when btw is unavailable. Reuses btw rather than reimplementing skill /
# README / context-file creation.
register_btw_task_tools <- function(chat, settings = list()) {
  enabled <- isTRUE(settings$btw_tasks) ||
    isTRUE(getOption("codeagent.btw_tasks", FALSE))
  if (!enabled || !requireNamespace("btw", quietly = TRUE)) return(invisible(chat))
  builders <- list(
    btw::btw_task_create_skill,
    btw::btw_task_create_readme,
    btw::btw_task_create_btw_md
  )
  for (b in builders) {
    tryCatch({
      tool <- b(client = chat, mode = "tool")
      if (!is.null(tool)) chat$register_tool(tool)
    }, error = function(e) NULL)
  }
  invisible(chat)
}

#' Run a btw task with a codeagent client (reuse, not reinvent)
#'
#' Thin wrapper over [btw::btw_task()] so codeagent users can run any
#' markdown-defined btw task with their existing client's chat.
#'
#' @param path Path to a task markdown file (see [btw::btw_task()]).
#' @param client A codeagent client or an `ellmer::Chat` (its chat is reused).
#' @param mode One of `"console"`, `"app"`, `"client"`, `"tool"`.
#' @param ... Passed to [btw::btw_task()].
#' @return Whatever [btw::btw_task()] returns for the chosen mode.
#' @export
codeagent_task <- function(path, client = NULL, mode = "console", ...) {
  if (!requireNamespace("btw", quietly = TRUE))
    stop("btw is required for codeagent tasks (install posit-dev/btw).")
  btw::btw_task(path, ..., client = .as_ellmer_chat(client), mode = mode)
}

#' Create a skill via btw's guided task (reuse)
#' @inheritParams codeagent_task
#' @param ... Passed to [btw::btw_task_create_skill()].
#' @return See [btw::btw_task_create_skill()].
#' @export
codeagent_create_skill <- function(client = NULL, mode = "console", ...) {
  if (!requireNamespace("btw", quietly = TRUE))
    stop("btw is required (install posit-dev/btw).")
  btw::btw_task_create_skill(..., client = .as_ellmer_chat(client), mode = mode)
}

#' Create a polished README via btw's guided task (reuse)
#' @inheritParams codeagent_task
#' @param ... Passed to [btw::btw_task_create_readme()].
#' @return See [btw::btw_task_create_readme()].
#' @export
codeagent_create_readme <- function(client = NULL, mode = "console", ...) {
  if (!requireNamespace("btw", quietly = TRUE))
    stop("btw is required (install posit-dev/btw).")
  btw::btw_task_create_readme(..., client = .as_ellmer_chat(client), mode = mode)
}

#' Initialise a project-context file (btw.md) via btw's guided task (reuse)
#' @inheritParams codeagent_task
#' @param ... Passed to [btw::btw_task_create_btw_md()].
#' @return See [btw::btw_task_create_btw_md()].
#' @export
codeagent_init_context <- function(client = NULL, mode = "console", ...) {
  if (!requireNamespace("btw", quietly = TRUE))
    stop("btw is required (install posit-dev/btw).")
  btw::btw_task_create_btw_md(..., client = .as_ellmer_chat(client), mode = mode)
}
