#' @title Jupyter Notebook Tools
#' @description NotebookEdit and NotebookRead tools for codeagent.
#'   Operates on `.ipynb` JSON files.
#' @name tools_notebook
#' @keywords internal
NULL

# ---------------------------------------------------------------------------
# NotebookRead tool
# ---------------------------------------------------------------------------

#' Create the NotebookRead tool
#'
#' @return An `ellmer::tool()` object.
#' @export
notebook_read_tool <- function() {
  ellmer::tool(
    name = "NotebookRead",
    fun = function(notebook_path) {
      path <- normalizePath(notebook_path, mustWork = FALSE)
      if (!file.exists(path))
        return(paste0("[Error] Notebook not found: ", notebook_path))

      tryCatch({
        nb     <- jsonlite::fromJSON(path, simplifyVector = FALSE)
        cells  <- nb[["cells"]] %||% list()
        output <- character(length(cells))

        for (i in seq_along(cells)) {
          cell        <- cells[[i]]
          cell_type   <- cell[["cell_type"]] %||% "unknown"
          source      <- paste(unlist(cell[["source"]] %||% ""), collapse = "")
          cell_id     <- cell[["id"]] %||% as.character(i - 1L)
          exec_count  <- cell[["execution_count"]]
          exec_str    <- if (!is.null(exec_count) && !is.na(exec_count))
            paste0(" [", exec_count, "]") else ""

          header <- paste0("Cell ", i - 1L, " (", cell_type, exec_str,
                           ", id=", cell_id, "):")

          # Collect cell outputs
          outputs <- cell[["outputs"]] %||% list()
          out_lines <- vapply(outputs, function(o) {
            otype <- o[["output_type"]] %||% ""
            if (otype %in% c("stream", "display_data", "execute_result")) {
              txt <- o[["text"]] %||% o[["data"]][["text/plain"]] %||% list()
              paste(unlist(txt), collapse = "")
            } else ""
          }, character(1))
          out_lines <- out_lines[nzchar(out_lines)]

          parts <- c(header, source)
          if (length(out_lines) > 0L)
            parts <- c(parts, "Output:", paste(out_lines, collapse = "\n"))
          output[[i]] <- paste(parts, collapse = "\n")
        }
        result <- paste(output, collapse = "\n\n---\n\n")
        truncate_tool_result(result, "Read")
      }, error = function(e) {
        paste0("[Error] ", conditionMessage(e))
      })
    },
    description = paste0(
      "Read a Jupyter notebook (.ipynb) and return its cells with source and outputs."
    ),
    arguments   = list(
      notebook_path = ellmer::type_string(
        "Absolute path to the .ipynb file.", required = TRUE)
    ),
    annotations = ellmer::tool_annotations(
      title          = "NotebookRead",
      read_only_hint = TRUE
    )
  )
}

# ---------------------------------------------------------------------------
# NotebookEdit tool
# ---------------------------------------------------------------------------

#' Create the NotebookEdit tool
#'
#' @param mode Character. Permission mode.
#' @param rules List. Permission rules.
#' @param ask_fn Function or NULL.
#' @return An `ellmer::tool()` object.
#' @export
notebook_edit_tool <- function(mode = "default", rules = list(), ask_fn = NULL) {
  checker <- .make_permission_checker("NotebookEdit", mode, rules, ask_fn)

  ellmer::tool(
    name = "NotebookEdit",
    fun = function(notebook_path, new_source, cell_number = NULL,
                   cell_id = NULL, cell_type = "code",
                   edit_mode = "replace") {
      if (!checker(list(file_path = notebook_path)))
        return(paste0("[Permission denied] NotebookEdit: ", notebook_path))

      path <- normalizePath(notebook_path, mustWork = FALSE)
      if (!file.exists(path))
        return(paste0("[Error] Notebook not found: ", notebook_path))

      tryCatch({
        nb    <- jsonlite::fromJSON(path, simplifyVector = FALSE)
        cells <- nb[["cells"]] %||% list()

        # Resolve target cell index (0-indexed from API, 1-indexed in R)
        idx <- NULL
        if (!is.null(cell_id)) {
          for (i in seq_along(cells)) {
            if (identical(cells[[i]][["id"]], cell_id)) { idx <- i; break }
          }
          if (is.null(idx))
            return(paste0("[Error] Cell id not found: ", cell_id))
        } else if (!is.null(cell_number)) {
          idx <- as.integer(cell_number) + 1L  # 0-indexed -> 1-indexed
          if (idx < 1L || idx > length(cells))
            return(paste0("[Error] Cell number out of range: ", cell_number))
        }

        source_lines <- strsplit(new_source, "\n", fixed = TRUE)[[1]]

        if (identical(edit_mode, "delete")) {
          if (is.null(idx))
            return("[Error] cell_number or cell_id required for delete.")
          cells <- cells[-idx]
        } else if (identical(edit_mode, "insert")) {
          new_cell <- .make_nb_cell(cell_type, source_lines)
          # idx >= length(cells) means "insert after the last cell" == append.
          # The else branch is only reached when idx < length(cells), which
          # guarantees (idx+1):length(cells) is a valid ascending slice.
          if (is.null(idx) || idx >= length(cells)) {
            cells <- c(cells, list(new_cell))
          } else {
            cells <- c(cells[seq_len(idx)], list(new_cell),
                       cells[(idx + 1L):length(cells)])
          }
        } else {
          # replace (default)
          if (is.null(idx))
            return("[Error] cell_number or cell_id required for replace.")
          cells[[idx]][["source"]] <- as.list(
            paste0(source_lines, ifelse(seq_along(source_lines) < length(source_lines), "\n", ""))
          )
        }

        nb[["cells"]] <- cells
        writeLines(
          jsonlite::toJSON(nb, auto_unbox = TRUE, pretty = TRUE, null = "null"),
          path
        )
        paste0("NotebookEdit applied (", edit_mode, ") to: ", notebook_path)
      }, error = function(e) {
        paste0("[Error] ", conditionMessage(e))
      })
    },
    description = paste0(
      "Edit a Jupyter notebook cell. edit_mode: 'replace' (default), 'insert', 'delete'. ",
      "Specify target by cell_number (0-indexed) or cell_id."
    ),
    arguments   = list(
      notebook_path = ellmer::type_string(
        "Absolute path to the .ipynb file.", required = TRUE),
      new_source    = ellmer::type_string(
        "New cell source code or markdown.", required = TRUE),
      cell_number   = ellmer::type_number(
        "0-indexed cell number.", required = FALSE),
      cell_id       = ellmer::type_string(
        "Cell ID string.", required = FALSE),
      cell_type     = ellmer::type_enum(
        values = c("code", "markdown"),
        description = "Cell type for insert mode (default 'code').",
        required = FALSE),
      edit_mode     = ellmer::type_enum(
        values = c("replace", "insert", "delete"),
        description = "Edit operation (default 'replace').",
        required = FALSE)
    ),
    annotations = ellmer::tool_annotations(
      title            = "NotebookEdit",
      read_only_hint   = FALSE,
      destructive_hint = FALSE
    )
  )
}

# ---------------------------------------------------------------------------
# Register notebook tools
# ---------------------------------------------------------------------------

#' Register notebook tools to an ellmer Chat object
#'
#' @param chat An `ellmer::Chat` object.
#' @param mode Character. Permission mode.
#' @param rules List. Permission rules.
#' @param ask_fn Function or NULL.
#' @return Invisibly returns `chat`.
#' @export
register_notebook_tools <- function(chat, mode = "default",
                                     rules = list(), ask_fn = NULL) {
  chat$register_tool(notebook_read_tool())
  chat$register_tool(notebook_edit_tool(mode, rules, ask_fn))
  invisible(chat)
}

# ---------------------------------------------------------------------------
# Internal helper
# ---------------------------------------------------------------------------

.make_nb_cell <- function(cell_type, source_lines) {
  src <- as.list(
    paste0(source_lines,
           ifelse(seq_along(source_lines) < length(source_lines), "\n", ""))
  )
  id  <- paste0(sample(c(letters, 0:9), 8, replace = TRUE), collapse = "")
  if (identical(cell_type, "markdown")) {
    list(cell_type = "markdown", id = id, metadata = list(), source = src)
  } else {
    list(cell_type      = "code",
         id             = id,
         metadata       = list(),
         source         = src,
         outputs        = list(),
         execution_count = NULL)
  }
}
