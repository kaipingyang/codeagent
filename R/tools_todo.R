#' @title TodoWrite Tool
#' @description A single tool that lets the model maintain a persistent markdown
#'   TODO list for the current session, mirroring Claude Code's TodoWrite. Unlike
#'   the in-memory `TaskCreate`/`TaskList` tools (`tools_task.R`), the todo list
#'   is written to `~/.codeagent/todos/<session>.md` so it survives across turns
#'   and sessions and is human-readable on disk.
#' @name tools_todo
#' @keywords internal
NULL

# Directory holding per-session todo markdown files.
.todos_dir <- function() {
  d <- file.path(.get_codeagent_dir(), "todos")
  dir.create(d, showWarnings = FALSE, recursive = TRUE)
  d
}

# Resolve the todo file path for a session id (sanitised).
.todo_path <- function(session_id = "default") {
  sid <- gsub("[^A-Za-z0-9_.-]", "_", session_id %||% "default")
  file.path(.todos_dir(), paste0(sid, ".md"))
}

# Status -> checkbox / glyph for the rendered markdown.
.todo_glyph <- function(status) {
  switch(status,
    completed   = "[x]",
    in_progress = "[~]",
    "[ ]"        # pending / unknown
  )
}

# Render a list of todo items (each: list(content, status, [active_form])) to
# a markdown checklist string.
.render_todos <- function(items) {
  if (!length(items)) return("(no todos)\n")
  lines <- vapply(items, function(it) {
    status <- it$status %||% "pending"
    txt    <- it$content %||% it$subject %||% ""
    af     <- it$active_form %||% it$activeForm
    suffix <- if (identical(status, "in_progress") && !is.null(af) && nzchar(af))
      paste0("  _(", af, ")_") else ""
    paste0("- ", .todo_glyph(status), " ", txt, suffix)
  }, character(1))
  paste0(paste(lines, collapse = "\n"), "\n")
}

# Coerce the tool's `todos` argument (which arrives from ellmer as a list of
# lists, or a data.frame, depending on the backend) into a clean list of items.
.coerce_todos <- function(todos) {
  if (is.null(todos)) return(list())
  if (is.data.frame(todos)) {
    return(lapply(seq_len(nrow(todos)), function(i) as.list(todos[i, , drop = FALSE])))
  }
  if (is.list(todos)) return(todos)
  list()
}

#' Create the TodoWrite tool
#'
#' @param session_id Character. Session id used to name the todo file. The
#'   harness passes the live session id; defaults to `"default"`.
#' @return An `ellmer::tool()` object.
#' @export
todo_write_tool <- function(session_id = "default") {
  force(session_id)
  ellmer::tool(
    name = "TodoWrite",
    fun = function(todos) {
      items <- .coerce_todos(todos)
      md    <- .render_todos(items)
      path  <- .todo_path(session_id)
      header <- paste0("# Todos (", format(Sys.time(), "%Y-%m-%d %H:%M"), ")\n\n")
      tryCatch(writeLines(paste0(header, md), path),
               error = function(e) NULL)

      n_done <- sum(vapply(items, function(it)
        identical(it$status %||% "pending", "completed"), logical(1)))
      summary <- sprintf("Updated %d todo(s) (%d completed). Saved to %s.",
                         length(items), n_done, path)

      .tool_result2(summary, kind = "text", icon = "list-check",
                    title = sprintf("TodoWrite (%d items)", length(items)),
                    markdown = md,
                    payload = list(text = md, lang = "markdown"))
    },
    description = paste0(
      "Create or overwrite the session's TODO list (persistent markdown). ",
      "Pass the FULL list each time -- it replaces the previous one. Each item ",
      "has content, status (pending/in_progress/completed), and optional ",
      "active_form. Use this to track multi-step work."
    ),
    arguments = list(
      todos = ellmer::type_array(
        description = "The full ordered list of todo items.",
        items = ellmer::type_object(
          .description = "A single todo item.",
          content     = ellmer::type_string("What the todo is.", required = TRUE),
          status      = ellmer::type_string(
            "pending | in_progress | completed", required = TRUE),
          active_form = ellmer::type_string(
            "Present-continuous label shown when in_progress.", required = FALSE)
        )
      )
    ),
    annotations = ellmer::tool_annotations(
      title = "TodoWrite", read_only_hint = FALSE, destructive_hint = FALSE)
  )
}

#' Read the current todo list for a session
#'
#' @param session_id Character. Session id.
#' @return Character(1) markdown, or "" if no todo file exists.
#' @export
read_todos <- function(session_id = "default") {
  path <- .todo_path(session_id)
  if (!file.exists(path)) return("")
  paste(readLines(path, warn = FALSE), collapse = "\n")
}

#' Register the TodoWrite tool on a chat
#'
#' @param chat An `ellmer::Chat` object.
#' @param session_id Character. Session id for the todo file.
#' @return Invisibly `chat`.
#' @keywords internal
register_todo_tool <- function(chat, session_id = "default") {
  tryCatch(chat$register_tool(todo_write_tool(session_id)),
           error = function(e) NULL)
  invisible(chat)
}
