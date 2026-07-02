#' @title File System Tools
#' @description Read, Write, Edit, MultiEdit -- file manipulation with permission gating.
#' @name tools_fs
#' @keywords internal
NULL

# ---------------------------------------------------------------------------
# Read tool
# ---------------------------------------------------------------------------

#' Create the Read tool
#'
#' @param mode Character. Permission mode.
#' @param rules List. Permission rules.
#' @return An `ellmer::tool()` object.
#' @export
read_tool <- function(mode = "default", rules = list()) {
  ellmer::tool(
    name = "Read",
    fun = function(file_path, offset = NULL, limit = NULL, `_intent` = NULL) {
      r <- .safe_normalize_path(file_path)
      if (!is.null(r$error)) return(r$error)
      path <- r$path
      tryCatch({
        lines <- readLines(path, warn = FALSE)
        total <- length(lines)
        start <- if (!is.null(offset)) max(1L, as.integer(offset)) else 1L
        end   <- if (!is.null(limit))
          min(total, start + as.integer(limit) - 1L) else total
        if (start > end) return("")
        selected <- lines[start:end]
        numbered <- paste0(seq.int(start, end), "\t", selected)
        result   <- paste(numbered, collapse = "\n")
        result   <- truncate_tool_result(result, "Read")
        ext      <- tools::file_ext(path)
        fname    <- basename(path)
        range_str <- if (!is.null(offset) || !is.null(limit))
          sprintf(" (lines %d-%d)", start, end) else ""

        # right_output: code preview for the right panel
        .tool_result2(
          result,
          kind     = "code",
          icon     = "file-text",
          title    = sprintf("Read <code>%s</code>%s",
                             htmltools::htmlEscape(fname), range_str),
          markdown = sprintf("```%s\n%s\n```", ext, result),
          payload  = list(text = result,
                          lang = if (nzchar(ext)) ext else "text",
                          filename = fname)
        )
      }, error = function(e) {
        paste0("[Error] ", conditionMessage(e))
      })
    },
    description = paste0(
      "Read the contents of a file. Returns lines with line numbers. ",
      "Use offset and limit to read specific sections of large files."
    ),
    arguments = list(
      file_path = ellmer::type_string(
        "Absolute or relative path to the file.", required = TRUE),
      offset    = ellmer::type_number(
        "Line number to start reading from (1-indexed).", required = FALSE),
      limit     = ellmer::type_number(
        "Maximum number of lines to return.", required = FALSE),
      `_intent` = ellmer::type_string(
        "Brief description of why this file is being read.", required = FALSE)
    ),
    annotations = ellmer::tool_annotations(
      title          = "Read",
      read_only_hint = TRUE
    )
  )
}

# ---------------------------------------------------------------------------
# Write tool
# ---------------------------------------------------------------------------

#' Create the Write tool
#'
#' @param mode Character. Permission mode.
#' @param rules List. Permission rules.
#' @param ask_fn Function or NULL.
#' @return An `ellmer::tool()` object.
#' @export
write_tool <- function(mode = "default", rules = list(), ask_fn = NULL) {
  checker <- .make_permission_checker("Write", mode, rules, ask_fn)

  ellmer::tool(
    name = "Write",
    fun = function(file_path, content, `_intent` = NULL) {
      if (!checker(list(file_path = file_path))) {
        ellmer::tool_reject(paste0("Permission denied for Write: ", file_path))
      }
      tryCatch({
        dir.create(dirname(file_path), showWarnings = FALSE, recursive = TRUE)
        existed <- file.exists(file_path)
        writeLines(content, file_path)
        verb  <- if (existed) "Updated" else "Created"
        fname <- basename(file_path)
        .tool_result2(
          paste0(verb, ": ", file_path),
          kind    = "diff",
          icon    = if (existed) "pencil" else "file-earmark-plus",
          title   = sprintf("%s <code>%s</code>",
                            verb, htmltools::htmlEscape(fname)),
          payload = list(verb = verb, path = file_path, new = content)
        )
      }, error = function(e) {
        paste0("[Error] ", conditionMessage(e))
      })
    },
    description = paste0(
      "Create or overwrite a file with the given content. ",
      "Prefer Edit for targeted changes to existing files."
    ),
    arguments = list(
      file_path = ellmer::type_string(
        "Path to the file to create or overwrite.", required = TRUE),
      content   = ellmer::type_string(
        "Full content to write to the file.", required = TRUE),
      `_intent` = ellmer::type_string(
        "Brief description of why this file is being written.", required = FALSE)
    ),
    annotations = ellmer::tool_annotations(
      title            = "Write",
      read_only_hint   = FALSE,
      destructive_hint = TRUE
    )
  )
}

# ---------------------------------------------------------------------------
# Edit tool (exact string replacement)
# ---------------------------------------------------------------------------

#' Create the Edit tool
#'
#' @param mode Character. Permission mode.
#' @param rules List. Permission rules.
#' @param ask_fn Function or NULL.
#' @return An `ellmer::tool()` object.
#' @export
edit_tool <- function(mode = "default", rules = list(), ask_fn = NULL) {
  checker <- .make_permission_checker("Edit", mode, rules, ask_fn)

  ellmer::tool(
    name = "Edit",
    fun = function(file_path, old_string, new_string, replace_all = FALSE, `_intent` = NULL) {
      if (!checker(list(file_path = file_path))) {
        ellmer::tool_reject(paste0("Permission denied for Edit: ", file_path))
      }
      r <- .safe_normalize_path(file_path)
      if (!is.null(r$error)) return(r$error)
      path <- r$path
      tryCatch({
        content <- paste(readLines(path, warn = FALSE), collapse = "\n")
        # Uniqueness check (unless replace_all)
        if (!isTRUE(replace_all)) {
          m_list <- gregexpr(old_string, content, fixed = TRUE)[[1L]]
          count  <- if (length(m_list) == 1L && m_list[[1L]] == -1L) 0L
                    else length(m_list)
          if (count == 0L)
            return(paste0("[Error] old_string not found in ", file_path))
          if (count > 1L)
            return(paste0("[Error] old_string appears ", count,
                          " times \u2014 use replace_all=TRUE or provide more context."))
        }
        new_content <- if (isTRUE(replace_all))
          gsub(old_string, new_string, content, fixed = TRUE)
        else
          sub(old_string, new_string, content, fixed = TRUE)
        writeLines(new_content, path)
        .tool_result2(
          paste0("Edited: ", file_path),
          kind    = "diff",
          icon    = "pencil",
          title   = sprintf("Edit <code>%s</code>",
                            htmltools::htmlEscape(basename(file_path))),
          payload = list(verb = "Edited", path = file_path,
                         old = content, new = new_content)
        )
      }, error = function(e) {
        paste0("[Error] ", conditionMessage(e))
      })
    },
    description = paste0(
      "Perform an exact string replacement in a file. ",
      "old_string must appear exactly once (unless replace_all=TRUE). ",
      "Provide enough context to make old_string unique."
    ),
    arguments = list(
      file_path   = ellmer::type_string(
        "Path to the file to edit.", required = TRUE),
      old_string  = ellmer::type_string(
        "Exact text to find and replace.", required = TRUE),
      new_string  = ellmer::type_string(
        "Replacement text.", required = TRUE),
      replace_all = ellmer::type_boolean(
        "Replace all occurrences (default FALSE).", required = FALSE),
      `_intent` = ellmer::type_string(
        "Brief description of what this edit achieves.", required = FALSE)
    ),
    annotations = ellmer::tool_annotations(
      title            = "Edit",
      read_only_hint   = FALSE,
      destructive_hint = FALSE
    )
  )
}

# ---------------------------------------------------------------------------
# MultiEdit tool (batch edits in one file)
# ---------------------------------------------------------------------------

#' Create the MultiEdit tool
#'
#' Applies multiple `old_string -> new_string` replacements sequentially
#' to a single file in one call.
#'
#' @param mode Character. Permission mode.
#' @param rules List. Permission rules.
#' @param ask_fn Function or NULL.
#' @return An `ellmer::tool()` object.
#' @export
multi_edit_tool <- function(mode = "default", rules = list(), ask_fn = NULL) {
  checker <- .make_permission_checker("MultiEdit", mode, rules, ask_fn)

  ellmer::tool(
    name = "MultiEdit",
    fun = function(file_path, edits, `_intent` = NULL) {
      if (!checker(list(file_path = file_path))) {
        ellmer::tool_reject(paste0("Permission denied for MultiEdit: ", file_path))
      }
      r <- .safe_normalize_path(file_path)
      if (!is.null(r$error)) return(r$error)
      path <- r$path
      tryCatch({
        content <- paste(readLines(path, warn = FALSE), collapse = "\n")
        orig_content <- content
        applied <- 0L
        for (edit in edits) {
          old <- edit[["old_string"]] %||% ""
          new <- edit[["new_string"]] %||% ""
          ra  <- isTRUE(edit[["replace_all"]])
          if (ra) {
            content <- gsub(old, new, content, fixed = TRUE)
          } else {
            ml  <- gregexpr(old, content, fixed = TRUE)[[1L]]
            cnt <- if (length(ml) == 1L && ml[[1L]] == -1L) 0L else length(ml)
            if (cnt != 1L) {
              return(paste0("[Error] Edit ", applied + 1L, ": old_string found ",
                            cnt, " times. Aborting."))
            }
            content <- sub(old, new, content, fixed = TRUE)
          }
          applied <- applied + 1L
        }
        writeLines(content, path)
        .tool_result2(
          paste0("Applied ", applied, " edit(s) to: ", file_path),
          kind    = "diff",
          icon    = "pencil-square",
          title   = sprintf("MultiEdit <code>%s</code> (%d edits)",
                            htmltools::htmlEscape(basename(file_path)), applied),
          payload = list(verb = sprintf("MultiEdit (%d)", applied),
                         path = file_path, old = orig_content, new = content)
        )
      }, error = function(e) {
        paste0("[Error] ", conditionMessage(e))
      })
    },
    description = paste0(
      "Apply multiple string replacements to a single file in sequence. ",
      "Each edit is an object with old_string, new_string, and optional replace_all."
    ),
    arguments = list(
      file_path = ellmer::type_string(
        "Path to the file to edit.", required = TRUE),
      edits     = ellmer::type_array(
        items = ellmer::type_object(
          "A single edit operation.",
          old_string  = ellmer::type_string("Text to find.", required = TRUE),
          new_string  = ellmer::type_string("Replacement text.", required = TRUE),
          replace_all = ellmer::type_boolean(
            "Replace all occurrences.", required = FALSE)
        ),
        description = "Array of edit operations to apply in order."
      ),
      `_intent` = ellmer::type_string(
        "Brief description of what these edits achieve.", required = FALSE)
    ),
    annotations = ellmer::tool_annotations(
      title            = "MultiEdit",
      read_only_hint   = FALSE,
      destructive_hint = FALSE
    )
  )
}

# ---------------------------------------------------------------------------
# Glob tool
# ---------------------------------------------------------------------------

# Portable ** glob via list.files().
# Sys.glob("**/*.R") only works on Linux (glibc GLOB_STAR); silent on macOS/Windows.
# This helper provides a cross-platform fallback whenever the pattern contains **.
.glob_with_starstar <- function(base, pattern) {
  m         <- regexpr("\\*\\*", pattern, perl = TRUE)
  prefix    <- if (m > 1L) substr(pattern, 1L, m - 1L) else ""
  remainder <- substr(pattern, m[[1L]] + 2L, nchar(pattern))
  # Strip leading slash from the tail to get a file-level pattern.
  file_pat  <- sub("^[/\\\\]+", "", remainder)

  search_root <- normalizePath(
    if (nzchar(prefix))
      file.path(base, sub("[/\\\\]+$", "", prefix))
    else
      base,
    mustWork = FALSE
  )
  if (!dir.exists(search_root)) return(character(0))

  all_files <- list.files(search_root, recursive = TRUE, full.names = TRUE)
  if (length(all_files) == 0L || !nzchar(file_pat)) return(all_files)

  # When file_pat has no path separator, match only the filename portion.
  # When it does (e.g. "foo/*.R"), match the relative path.
  rx <- utils::glob2rx(file_pat)
  if (!grepl("[/\\\\]", file_pat, perl = TRUE)) {
    all_files[grepl(rx, basename(all_files))]
  } else {
    rel_paths <- substring(all_files, nchar(search_root) + 2L)
    all_files[grepl(rx, rel_paths)]
  }
}

